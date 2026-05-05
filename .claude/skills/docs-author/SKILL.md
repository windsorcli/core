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

Per-module README at `terraform/<module>/README.md`. Each is split into a
hand-authored prose section above the `<!-- BEGIN_TF_DOCS -->` marker and
the auto-generated terraform-docs reference between markers. `task docs`
uses `terraform-docs --output-mode inject` so the prose survives
regeneration.

Section order for the prose (cousin of the Kustomize add-on template,
adapted for Terraform):

1. **Frontmatter + purpose** — `title: <module-path>` and a one-line description; one-paragraph elevator pitch under the H1.
2. **Wiring** — what materializes in a blueprint when the module fires. Show a concrete `terraform:` block with realistic input values (not raw facet expressions), then explain in prose how each input flows from `values.yaml` through the facet — naming the relevant schema fields (e.g. "follows the top-level `topology` field") and calling out inputs that aren't user-tunable when relevant ("set by the facet on the Talos path, not exposed as a user knob"). Describe gating in user-facing schema terms (e.g. "rendered on Talos clusters (`cluster.driver: talos`)") — never `talos_provisioned`, `eks_enabled`, `cni_effective`, or other internal facet derivations. Reach for a table only if the mapping is dense or many inputs need parallel structure; for most modules a few sentences are clearer.
3. **Dependencies** — other Terraform modules this `dependsOn`, plus relevant Kustomize add-ons (forward and reverse).
4. **Operations (optional)** — only include if there are **verified, observed** failure modes worth documenting. Reference docs aren't the place to brainstorm "what could go wrong if a value is set to X" by reading the source — that's speculation, and a reader who hits a *different* error and doesn't find it here is misled into thinking the module is well-trodden when it isn't. Leave the section out for new modules; add it as real issues come up. When you do include it, lead with the symptom (error string, observed behaviour) and follow with a verified fix.
5. **Security (optional)** — only state what's verifiable from the module source: namespace, capabilities/privilege flags, what the module reads or writes. Don't claim how credentials or kubeconfig flow unless that's visible in the module itself; provider plumbing typically lives outside the module and is not safe to characterize from inside.
6. **See also** — sibling modules and the cousin Kustomize add-on(s).
7. **Override-path callout** — a one-line blockquote immediately above `<!-- BEGIN_TF_DOCS -->` reminding readers they can override any input below from their context. Format: `> Override any input below from your context without editing the blueprint by adding contexts/<context>/terraform/<file>.tfvars (named after the blueprint entry's name).` The `<file>` portion is the entry's `name` if present (e.g. `cni.tfvars`); otherwise the `path` with `/` preserved (e.g. `cni/cilium.tfvars`). Use the specific path for this module, not the general rule.

8. **Auto-generated reference** (existing, between `BEGIN_TF_DOCS`/`END_TF_DOCS` markers — kept by `task docs`).

Skip Mermaid diagrams by default. The auto-generated `### Resources` table already enumerates what the module creates; a diagram that just re-draws those resources is filler. Only add one if you can name a specific relationship the diagram captures that prose really can't — e.g. a non-obvious resource graph with ordering or cross-references hard to follow as a list. Multi-actor handoffs (a Terraform module that hands off to Flux, etc.) are usually fine in one sentence of prose. When in doubt, ship without and re-evaluate after real reader feedback.

Don't claim platform support for paths that aren't validated by tests. If a module has wiring on a platform that isn't exercised end-to-end, omit it from the README — the wiring exists in the facet for those who go looking.

For the auto-generated section: don't hand-edit. If the variable / output descriptions read awkwardly (e.g. mention untested platforms), fix them in the source `variables.tf` / `outputs.tf` and re-run `task docs`.

Verify every "this module creates X" claim against the actual `resource "..."` declarations in `main.tf` before writing the lead, the Flow diagram, or the Security section. The module's resource set is often narrower than the surrounding system suggests — e.g. a Flux installer module might install controllers but not the GitRepository / root Kustomization that drive reconciliation. Diagrams and prose should describe what *this module* does, with anything bootstrapped elsewhere noted as such.

High-level "what is Terraform in Windsor" stays on the site under `/docs/components/terraform`.

## Kustomize stack operator guide (per top-level stack)

Author under `kustomize/<stack>/README.md` (nested stacks supported). After edits, run **`task docs:reference:kustomize`** or `node scripts/sync-kustomize-reference.mjs` to refresh **`docs/reference/kustomize/**`** (generated; do not hand-edit—change README and re-sync).

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

- [ ] Module or stack behavior that affects operators reflected in `docs/reference/` or stack README; run `task docs:reference:kustomize` when `kustomize/**/README.md` changed.
- [ ] Generated Terraform docs refreshed if inputs/outputs changed.
- [ ] Links to Blueprint schema/facets point at windsorcli.dev `/docs/blueprints/...`, not duplicate prose.
- [ ] No slug or path that implies generic blueprint authoring—that belongs on the website repo.

## Internal architecture note

[windsorcli.github.io `docs/plan.md` on GitHub](https://github.com/windsorcli/windsorcli.github.io/blob/main/docs/plan.md) — maintainer planning only; not published on windsorcli.dev.

Preview in the website repo from local checkouts: `npm run docs:vendor:local` then `npm run dev` (see website `README.md`; expects `../cli` and `../core` by default).
