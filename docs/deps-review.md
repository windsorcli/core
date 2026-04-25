# Dependency Update Reviewer — Design

A CI/CD workflow that reviews every `dependencies`-labeled PR, classifies what's changing, runs purpose-built analyzers per artifact type, and posts a single consolidated review comment. AI reasons over the analyzers' factual outputs; it does not produce facts of its own.

## Goals

- Catch the specific failure modes that matter for this repo: Terraform provider source swaps, Helm chart behavioral drift, container registry swaps, GitHub Action owner swaps, vendored-file tampering, and out-of-scope edits smuggled into dependency PRs.
- Deterministic analyzers do the load-bearing work. AI handles prioritization and narrative.
- Fast enough to run on every dependency PR: target budget ~5-8 minutes total.
- Fails gracefully: if AI is unavailable, analyzer output still posts as a fallback comment.

## Non-goals

- CVE scanning — covered by Dependabot / osv-scanner.
- License auditing — separate concern.
- Deep transitive dependency trees — Renovate tracks direct deps; that's enough.
- Executing or sandboxing package code — out of scope; let trivy/grype/snyk do image content scans.
- Replacing Renovate — this complements it by reviewing what Renovate (and humans) propose.

## Trigger

```yaml
on:
  pull_request:
    types: [opened, synchronize, labeled]

jobs:
  triage:
    if: contains(github.event.pull_request.labels.*.name, 'dependencies')
    ...
```

Keyed on the `dependencies` label. Renovate applies this label automatically (configured in [.github/renovate.json](../.github/renovate.json)). Humans bumping a dep manually opt in by adding the label.

## Architecture

Three stages:

```
┌─────────┐   ┌──────────────────────────────────┐   ┌───────────┐
│ Triage  │──▶│ Per-type analyzers (parallel)    │──▶│ AI summary│
│ (~30s)  │   │  tf · helm · image · action · …  │   │ (~2-3 min)│
└─────────┘   └──────────────────────────────────┘   └───────────┘
```

### Stage 1 — Triage (`~30s`)

One fast job that reads the PR diff and classifies every changed file into a bucket. Emits a JSON manifest describing what kind of changes are in the PR.

Responsibilities:

- Classify each changed file into one of: `tf-provider`, `helm-chart`, `container-image`, `gh-action`, `vendored-crd`, `vendored-dashboard`, `scope-violation`, or `unknown`.
- Emit a structured JSON manifest consumed by downstream jobs.
- Fast-fail on scope violations — any file outside the expected dep-change path set fails the whole review (see "Gating").

Expected dep-change path set:

- `*.tf`, `*.terraform.lock.hcl`
- `**/helm-release.yaml`, `**/values.yaml`
- `.github/workflows/*.yaml`, `.github/workflows/*.yml`
- `kustomize/**/crds/*.yaml`
- `kustomize/observability/grafana/dashboards/**`

Anything else in a `dependencies`-labeled PR is a scope violation.

### Stage 2 — Per-type analyzers (parallel)

Each analyzer runs only when relevant artifacts changed, based on triage output. Each emits a `findings.json` with a standard shape:

```json
{
  "analyzer": "helm-chart",
  "artifact": "cilium",
  "old_version": "1.16.19",
  "new_version": "1.17.0",
  "verdict": "warn",
  "findings": [
    {
      "category": "rbac",
      "severity": "medium",
      "detail": "ClusterRole cilium-agent gains verbs [patch, update, delete] on ciliumidentities",
      "evidence": "helm-diff line 1847"
    }
  ]
}
```

Verdict values: `ok`, `warn`, `fail`. Any `fail` fails the PR check; `warn` surfaces in the comment but is non-blocking by default.

#### `tf-provider` analyzer

- Grep the diff for `source =` changes. Any change = `fail` (real renovate bumps never change the source).
- For new `version =` values, fetch the provider's GitHub release and verify the hashes in `.terraform.lock.hcl` match the release's published SHA256SUMS.
- Detect new providers added to any `required_providers` block. New trust anchor = `warn`, must be acknowledged in review.

All deterministic. Tools: `git diff`, `grep`, `gh api`.

#### `helm-chart` analyzer

The highest-value analyzer. The key insight: don't try to audit upstream chart authors' supply chains — audit what the chart actually deploys.

- Extract `chart`, `version`, `sourceRef`, and inline `values` from old and new `HelmRelease` YAML (use `yq`).
- `helm template` both versions to temp directories.
- Run a structured manifest diff. Categorize changes:
  - **Images**: registry, repo path, tag. Registry change = `fail`; repo path change = `fail`; tag/digest change = `ok`.
  - **RBAC**: new verbs, new resources, new subjects, new ClusterRole/ClusterRoleBinding. Permission expansion = `warn` with detail.
  - **Webhooks**: new ValidatingWebhookConfiguration or MutatingWebhookConfiguration. `failurePolicy: Fail` = `warn` (operational risk).
  - **Privilege**: new container with `privileged: true`, `hostNetwork`, `hostPath`, additional capabilities, or new ServiceAccount token automount = `warn`.
  - **Kinds**: new resource types the chart didn't create before (CRDs, Jobs, CronJobs) = `warn` for visibility.
- Use the HelmRelease's declared values. A default-values render is simpler but misses repo-specific config; using the actual values in this repo gives a truer picture.

Deterministic. Tools: `yq`, `helm`, a YAML-walking diff script. AI does not judge RBAC/webhook changes — it only summarizes the findings in Stage 3.

Runtime: ~60s per chart. Parallelize by running one analyzer job per changed chart via a matrix.

#### `container-image` analyzer

- Regex the diff for digest-pinned image references (`@sha256:...`).
- For each change: compare old vs new reference on registry, repo path, and tag.
- Registry change = `fail`. Repo path change = `fail`. Tag or digest change = `ok` (if nothing else flagged).
- Optional: `crane manifest` or equivalent to verify the new digest resolves in the registry.

Deterministic. Tools: `git diff`, `grep`, optionally `crane`.

#### `gh-action` analyzer

- For each `uses: owner/repo@SHA` change in `.github/workflows/*.yaml`:
  - Verify `owner/repo` unchanged. Change = `fail`.
  - Verify new SHA corresponds to a tag in the target repo (`gh api repos/owner/repo/tags`). No tag = `warn` (SHA could be a random commit).
  - Fetch `action.yml` at old and new SHA. Diff: new required inputs, new permissions accessed, new outputs. Flag any of those.

Deterministic. Tools: `gh api`, `curl`, `diff`.

#### `vendored-crd` analyzer

- Each vendored CRD file in `kustomize/**/crds/` is expected to have a header comment naming its upstream source (the Gateway API file at [kustomize/gateway/base/crds/](../kustomize/gateway/base/crds/) is the model).
- Parse the source URL from the header.
- `curl` the upstream, byte-diff against the committed file. Any non-zero diff = `fail`.

Deterministic. Tools: `curl`, `cmp`.

#### `vendored-dashboard` analyzer

Already covered by the existing `Validate vendored assets` step in the `code-checks` job (runs `task dashboards` and asserts no diff). No new analyzer needed — the deps-review orchestrator just asserts `code-checks` passed.

#### `scope-violation` detector

- List changed files.
- If any file isn't in the expected dep-change path set (see Stage 1), emit a `fail` finding with the file path.
- This is the bot-impersonation detector — catches an attacker who forged a renovate PR and snuck in an RBAC manifest edit.

Deterministic. Tools: `git diff`, a simple path-match.

### Stage 3 — AI summarizer (`~2-3 min`)

One job that collects every `findings.json` from Stage 2, plus the PR title and diff summary, and writes a single consolidated PR comment.

Claude's job in this stage:

- **Synthesize**: one coherent table + prose summary across all analyzers.
- **Prioritize**: surface the highest-severity findings first; short-form the routine ones.
- **Correlate**: e.g., "this chart bump AND its primary container image changed digests in the same PR — verify they match the chart's signed release."
- **Write narrative for `warn` findings only**: explain *why* the analyzer flagged it and what a reviewer should check.

Claude does NOT:

- Produce factual claims not present in `findings.json`.
- Make fresh network calls to verify things.
- Run analyzers itself or second-guess their verdicts.

Strict output schema (markdown table + prose), enforced by the prompt. Comment is upserted via a stable marker (`<!-- deps-review -->`) so re-runs update in place.

Budget: `max-turns 40`, step timeout 5 min.

## PR comment shape

```markdown
<!-- deps-review -->
## Dependency review

**7 artifacts changed · 1 flag**

| Artifact | Type | Change | Verdict |
|---|---|---|---|
| kreuzwerker/docker | tf-provider | 4.0.0 → 4.2.0 | ok |
| cilium | helm-chart | 1.16.19 → 1.17.0 | warn |
| actions/checkout | gh-action | <SHA> → <SHA> (tag v6.0.2) | ok |
| … | | | |

### ⚠ cilium 1.16.19 → 1.17.0
- 2 new images on `quay.io/cilium/*` (registry unchanged)
- `cilium-agent` ClusterRole: +3 verbs (`patch`, `update`, `delete`) on `ciliumidentities`
- 1 new MutatingWebhookConfiguration with `failurePolicy: Fail`

Standard for a minor cilium bump; the new webhook's `failurePolicy: Fail` means admissions block during cilium-agent unavailability — acceptable if cilium has been stable in this repo.
<!-- /deps-review -->
```

## Gating

Job-level pass/fail rules:

- Any analyzer verdict = `fail` → job fails → PR check fails.
- All `ok` or any `warn` → job passes → PR comment posted, non-blocking.
- Scope violation → job fails immediately, no analyzers run.

The `deps-review` check should be added to branch protection as a required status check.

## Graceful degradation

If Claude (Stage 3) fails or times out, the workflow still posts a fallback comment built directly from the raw `findings.json` outputs — less polished but factually complete. The deterministic analyzers are the load-bearing logic; AI is convenience, not correctness.

## File layout

```
.github/workflows/deps-review.yaml           orchestrator
.github/scripts/deps-review/
  triage.sh                                  stage 1
  analyze-tf-provider.sh                     stage 2 analyzers
  analyze-helm-chart.sh
  analyze-container-image.sh
  analyze-gh-action.sh
  analyze-vendored-crd.sh
  check-scope.sh
  summarize-findings.py                      prepares Claude input
  fallback-comment.py                        Stage-3 degradation
docs/deps-review.md                          this file
```

## Implementation order

Iterative rollout — each step lands in its own PR, value accrues incrementally:

1. **Triage + scope-violation detector.** Gets the structural scaffolding in place; fails loudly on scope violations alone.
2. **`gh-action` analyzer.** Easiest real analyzer: only touches GitHub API.
3. **`container-image` analyzer.** Simple regex + registry identity check.
4. **`tf-provider` analyzer.** Adds GitHub release hash verification.
5. **`vendored-crd` analyzer.** Adds upstream fetch + byte-diff.
6. **`helm-chart` analyzer.** The meaty one — template + structured diff. Build last because it's the most complex.
7. **AI summarizer.** Once all analyzers emit structured findings, wire Claude to synthesize them.

Each stage has independent value. The AI summarizer is the last piece because it has nothing to summarize until the analyzers exist.

## Open questions

- **Helm diff tooling**: build a custom YAML walker, or adopt [helm-diff](https://github.com/databus23/helm-diff) plugin? Custom is more tailored to the categories we care about (RBAC, webhooks, privilege) but more code to maintain.
- **Chart rendering with HelmRelease values vs defaults**: using actual values gives a truer picture but requires extracting them from the HelmRelease YAML with `yq`. Defaults-only is simpler. Start with defaults; upgrade to values-aware if we find meaningful differences.
- **False-positive budget**: the `warn` verdict should not fail the PR by default, but enough noise trains reviewers to ignore the bot. Review warn-rate after first month and tighten categories that produce noise.
- **`container-image` registry allowlist**: should the analyzer have an explicit allowlist of trusted registries (`ghcr.io`, `quay.io`, `registry.k8s.io`, `docker.io`)? An image moving *to* `docker.io` might be a regression for us if we prefer `ghcr.io`.
