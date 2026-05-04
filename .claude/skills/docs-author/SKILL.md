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

## Kustomize stack operator guide (per top-level stack)

For each significant stack under `kustomize/` (e.g. dns, csi), maintain **one** operator-oriented README (source location agreed with ingest—often `kustomize/<stack>/README.md` normalized into `docs/reference/kustomize/<stack>.md`, or authored directly under `docs/reference/kustomize/`).

Use this section order where applicable:

1. **Purpose** — what this subtree owns.
2. **Dependencies** — other stacks, CRDs, cloud prereqs.
3. **Blueprint wiring** — minimal `blueprint.yaml` fragment (`source` pointing at this blueprint, `path`, `components`).
4. **Substitutions / vars** — table: name, default, required, effect.
5. **Components** — Kustomize `components/` and when to enable each.
6. **Operations** — upgrade, rollback, common failures, observability.
7. **Security** — RBAC, secrets, network policy when relevant.

Align structure with existing kustomize conventions: see `.claude/skills/kustomize-author/SKILL.md`. Terraform module docs should align with `.claude/skills/terraform-style/SKILL.md` where applicable.

## Compatibility

- Keep a single **blueprint-scoped** matrix (CLI minimum, Kubernetes, Flux) in `docs/reference/compatibility.md` (or equivalent)—“running **this** blueprint,” not generic Windsor marketing.

## PR checklist

- [ ] Module or stack behavior that affects operators reflected in `docs/reference/` or stack README.
- [ ] Generated Terraform docs refreshed if inputs/outputs changed.
- [ ] Links to Blueprint schema/facets point at windsorcli.dev `/docs/blueprints/...`, not duplicate prose.
- [ ] No slug or path that implies generic blueprint authoring—that belongs on the website repo.

## Internal architecture note

[windsorcli.github.io `docs/plan.md` on GitHub](https://github.com/windsorcli/windsorcli.github.io/blob/main/docs/plan.md) — maintainer planning only; not published on windsorcli.dev.
