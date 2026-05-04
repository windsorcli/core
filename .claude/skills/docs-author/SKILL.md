---
name: docs-author
description: Author and maintain reference Markdown for the core Windsor blueprint for ingestion into windsorcli.github.io. Use when writing docs under docs/, Terraform module reference, Kustomize stack operator guides (README per stack), or compatibility matrices.
---

# Core blueprint docs author

## Apply when

- Adding or changing Terraform modules, Kustomize stacks, or blueprint layout in ways operators must understand.
- Writing or refreshing `docs/reference/**` or stack-level `README.md` files that ship as blueprint reference.
- Defining or updating compatibility (CLI, Kubernetes, Flux) for **this** blueprint.

## Do not apply when

- Only changing implementation with no operator-facing contract (and no request to update reference)—still update reference if behavior users rely on changed.

## Contract with the docs site

**Core is a blueprint**, not a separate product tier. Reference from this repo materializes under the **blueprint reference** URL prefix (not generic “how to write a blueprint,” which lives under `/docs/blueprints/*` on the site).

| Author in this repo | Materialized slug prefix | Public URL prefix |
|---------------------|--------------------------|-------------------|
| `docs/reference/terraform/**` (generated) | `reference/blueprints/core/terraform/**` | `https://www.windsorcli.dev/docs/reference/blueprints/core/terraform/**` |
| `docs/reference/kustomize/**` or per-stack README → normalized MD | `reference/blueprints/core/kustomize/**` | `https://www.windsorcli.dev/docs/reference/blueprints/core/kustomize/**` |
| `docs/reference/compatibility.md`, `layout.md`, etc. | `reference/blueprints/core/*` | `https://www.windsorcli.dev/docs/reference/blueprints/core/*` |

Exact glob roots are finalized with the website `docs:vendor` script; treat the **public URL prefix** column as the stable link target for cross-repo links.

**Editorial split:** `/docs/blueprints/*` on the site = Blueprint API, schema, facets for **any** author. Pages under `/docs/reference/blueprints/core/*` = **what is inside this blueprint release** (modules, stacks, substitutions).

## Frontmatter (Markdown)

- `title` (required), `description` (recommended).
- Optional: `sidebar_order` for ingest nav.

## Voice

- **Reference only:** imperative, tables for inputs/vars, no marketing copy.
- Link generic blueprint concepts to `https://www.windsorcli.dev/docs/blueprints/...` (schema, sharing, facets).

## Terraform reference

- Generate from modules in this repo with `task docs` (terraform-docs injected between `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers in each module's `README.md`). Commit the regenerated `terraform/<module-path>/README.md` (`cluster/talos`, `gitops/flux`, etc.). The site ingest pipeline mirrors these into `docs/reference/terraform/<module-path>/` per the path mapping above; contributors don't write into `docs/reference/` directly.
- Inputs, outputs, and gotchas belong here; high-level “what is Terraform in Windsor” stays on the site under `/docs/components/terraform`.

## Kustomize stack reference (per top-level stack)

For each significant stack under `kustomize/` (e.g. dns, pki, gateway), maintain **one** README at `kustomize/<stack>/README.md`, normalized by the website ingest into `docs/reference/blueprints/core/kustomize/<stack>.md`.

**Audience: both blueprint designers and operators.** Designers compose `blueprint.yaml` and need to know which components to wire for which environment. Operators run the stack and need to know what's inside it and how it fails. The format below serves both — recipes and components tables for designers, operations and security for operators.

### Section order

1. **Frontmatter and purpose** — `title` and `description` in frontmatter; one or two sentences below the H1 stating what the stack owns.
2. **Flow** — Mermaid diagram (` ```mermaid `) showing how the stack's pieces interact. Subgraph the namespaces; show external dependencies (cloud APIs, other stacks) as separate nodes. Mermaid renders natively on GitHub and on the docs site (which uses GFM); ASCII art is too cramped once a stack has more than two flows.
3. **Recipes** — three to five canonical configurations with copy-pasteable `kustomize:` fragments (e.g. local single-node, AWS production, addon enabled). Each recipe is the **materialized union** of components when multiple facets layer onto the same kustomize entry, not just one facet's contribution. The merge is additive in Windsor — design for that.
4. **Substitutions** — table with columns `Name`, `Required when`, `Effect and constraints`. Include real constraints (zone ID format, IP-pool membership, SAN coverage), not just "string". Don't add a "Required: yes" column when every row says yes — fold the gating condition into "Required when".
5. **Components** — exhaustive lookup table, one row per Kustomize component directory. Columns: `Component`, `Enable when`, `Effect`. Group by operator if the stack has more than one (e.g. `coredns/` and `external-dns/`). This is reference material, not first-read material; designers use it to find what `coredns/cilium` actually does.
6. **Dependencies** — table with `Stack` and `Reason`. Be specific about *why* — "needed for CRDs", "needed for the cluster issuer that signs etcd certs". A weak rationale ("for security") usually means the real reason wasn't traced.
7. **Operations** — stack-specific failure modes only. Skip generic Flux/Renovate behaviour (`HelmRelease retries 3×`, `Renovate opens PRs`) — that lives at the repo level. Lead with the symptom, then the cause, then the fix. Include a metrics/observability note if the stack exposes Prometheus endpoints.
8. **Security** — namespace PSA levels, certificate issuance and trust paths, IAM/identity per provider, scope of any cluster-wide policies. Not a checklist of best practices; specific facts about *this* stack.
9. **See also** — canonical facets (link to `contexts/_template/facets/*.yaml` files that wire the stack), related stacks under `kustomize/`, and the Blueprint schema page on windsorcli.dev.

### What NOT to include

- **Chart and image versions.** Pinned in `helm-release.yaml` with renovate markers; that's the source of truth. Mirroring versions in the README means Renovate PRs silently drift the docs.
- **Generic operations boilerplate.** "Flux retries failed reconciles", "DependencyNotReady means a dependency isn't ready" — applies to every stack, doesn't belong in any single one.
- **Diagrams as PNG/SVG attachments.** Use Mermaid. The site renders it; binary attachments are fragile through ingest.

### Authoring workflow

1. Read the canonical facet(s) under `contexts/_template/facets/*.yaml` that wire the stack — they encode dependsOn, conditional component selection, and substitutions. The stack README mirrors that information in human-readable form.
2. Walk the component tree to confirm directories exist and read the patches to confirm what each component actually does.
3. Read the helm-release files for namespace, dependsOn at the HelmRelease level, and any inline values that affect described behavior.
4. Write the README in the section order above.
5. **Audit before publishing.** Verify every claim against code: each component path exists, each substitution name appears as `${...}` somewhere, each dependency rationale matches the actual reason (a "for X" claim where X isn't in the manifest is a hallucination). Use file:line citations in commit messages or PR descriptions when the claim isn't immediately obvious from the file. Spawning an Explore subagent to audit the README against the code is a reliable way to catch drift; the cost is one extra round-trip and it routinely finds two to four real issues per first draft.

### VS Code preview caveat

VS Code's built-in Markdown preview does not render Mermaid by default. Install `bierner.markdown-mermaid` for local preview. GitHub renders it natively, and the docs site (GFM) renders it via the standard GitHub renderer.

Align structure with existing kustomize conventions: see `.claude/skills/kustomize-author/SKILL.md`. Terraform module docs should align with `.claude/skills/terraform-style/SKILL.md` where applicable. Worked examples: [kustomize/dns/README.md](../../../kustomize/dns/README.md), [kustomize/pki/README.md](../../../kustomize/pki/README.md).

## Compatibility

- Keep a single **blueprint-scoped** matrix (CLI minimum, Kubernetes, Flux) in `docs/reference/compatibility.md` (or equivalent)—“running **this** blueprint,” not generic Windsor marketing.

## PR checklist

- [ ] Module or stack behavior that affects operators reflected in `docs/reference/` or stack README.
- [ ] Generated Terraform docs refreshed if inputs/outputs changed.
- [ ] Stack README sections in the prescribed order; recipes show materialized component unions, not single-facet fragments.
- [ ] Diagrams are Mermaid, not ASCII or attached images.
- [ ] No chart/image version table in stack READMEs.
- [ ] Every component path, substitution name, and dependency rationale verified against the actual manifests (audit pass before commit).
- [ ] Links to Blueprint schema/facets point at windsorcli.dev `/docs/blueprints/...`, not duplicate prose.
- [ ] No slug or path that implies generic blueprint authoring—that belongs on the website repo.

## Internal architecture note

[windsorcli.github.io `docs/plan.md` on GitHub](https://github.com/windsorcli/windsorcli.github.io/blob/main/docs/plan.md) — maintainer planning only; not published on windsorcli.dev.
