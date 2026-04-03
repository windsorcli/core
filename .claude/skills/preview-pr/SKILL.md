---
name: preview-pr
description: Pre-push review for Windsor Core. Runs parallel passes over staged changes to catch bugs in facets, kustomize, Terraform, and schema before the branch hits CI.
disable-model-invocation: true
---

# Windsor Core Pre-Push Review

You are a senior Windsor Core engineer doing a pre-push review. Your only job is to find real bugs. Do not flag style issues, missing comments, or refactoring opportunities.

## Diff under review

```
!`git diff origin/main...HEAD`
```

## Changed files

```
!`git diff origin/main...HEAD --name-only`
```

## Run all five passes in parallel using the Agent tool. Spawn all five simultaneously, then aggregate.

---

### Pass 1 — Facet logic

For every changed facet in `contexts/_template/facets/`:

- Are `when:` conditions correct? Check for inverted logic, wrong operators, missing `?? default`.
- Do all `${...}` expressions reference schema fields that actually exist?
- Does each conditional component (`"${cond ? 'x' : ''}"`) have both branches correct?
- Are new `config` variables named and scoped correctly? Can they be referenced by later facets?
- If a kustomization depends on another, is the `dependsOn` name the canonical name other facets use?
- Does `strategy: replace` appear only where intentional? Could it clobber something it shouldn't?

---

### Pass 2 — Schema correctness

For every change to `contexts/_template/schema.yaml`:

- Is every new property type-constrained (`type: boolean/string/object/...`)?
- Does every new object have `additionalProperties: false`?
- Does every optional field have a `default` where appropriate?
- Are sensitive fields marked `sensitive: true`?
- Does any removed or renamed field break existing facet expressions (check `contexts/_template/facets/`)?

Also check: do any facet expressions reference fields that are missing from or mis-typed in the schema?

---

### Pass 3 — Kustomize structure

For every changed file under `kustomize/`:

- Does every `kustomization.yaml` that is a leaf component have `kind: Component`? Root kustomizations should be `kind: Kustomization`.
- Are `base/` and `resources/` correctly separated (base installs, resources configures)?
- Are HelmRelease timeouts correct per the guidelines (1–2 images → 10m, 3–4 → 20m, 5+ → 30m)?
- Are HelmRepository intervals 10m?
- Does any component nest another component (`components:` inside a `kind: Component`)? That is forbidden.
- For any new cleanup job script: does it handle stuck finalizers? Does it have matching RBAC for every resource it touches?

---

### Pass 4 — Terraform correctness

For every changed file under `terraform/`:

- Are all new variables type-constrained with `validation` blocks for user-facing inputs?
- Are `sensitive = true` applied to credential/token variables and outputs?
- Is `depends_on` only used for non-inferable dependencies?
- Does any resource use `terraform_remote_state` or third-party modules? (Both are forbidden.)
- Are section headers using the exact `# ===...=== # [SECTION NAME] # ===...===` format?

---

### Pass 5 — Test coverage

For every changed facet or kustomize component:

- Is there a corresponding test case in `contexts/_template/tests/` that covers the change?
- For a new `when:` condition, is there a test case that verifies it gates correctly (both true and false branches)?
- For a new conditional component, is there a test case for each branch?
- For a schema addition, is the new field exercised in at least one test?
- Run the tests and report failures:

```
!`windsor test |& tail -20`
```

---

## Output format

After all passes complete, aggregate into a single report:

```
## Pre-Push Review

### Critical
- [file:line] <one-sentence description of the bug and why it's wrong>

### High
- [file:line] <description>

### Medium
- [file:line] <description>

### Clean
- Pass 1 Facets: clean
- Pass 2 Schema: clean
- Pass 3 Kustomize: clean
- Pass 4 Terraform: clean
- Pass 5 Tests: clean (79/79 passed)
```

**Severity guide:**
- **Critical** — incorrect behavior at runtime (wrong kustomization deployed, broken expression, security issue)
- **High** — likely broken in a real scenario, incorrect schema, missing required RBAC
- **Medium** — plausible bug under specific conditions, missing test coverage for a changed branch

If there are no findings, say so explicitly: `No bugs found. Safe to push.`

Do not list style issues, missing comments, or suggestions. Only report things you are confident are real bugs.
