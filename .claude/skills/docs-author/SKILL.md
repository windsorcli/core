---
name: docs-author
description: Author and maintain reference Markdown for the core Windsor blueprint for ingestion into windsorcli.github.io. Use when writing docs under docs/, Terraform module reference, Kustomize stack operator guides (README per stack), or compatibility matrices.
---

# Core blueprint docs author

## Apply when

- Adding or changing Terraform modules, Kustomize stacks, or blueprint layout in ways operators must understand.
- Writing or refreshing the per-module/stack `README.md` files (under `kustomize/**` and `terraform/**`) that ship as blueprint reference.
- Defining or updating compatibility (CLI, Kubernetes, Flux) for **this** blueprint.

## Do not apply when

- Only changing implementation with no operator-facing contract (and no request to update reference)—still update reference if behavior users rely on changed.

## Contract with the docs site

**The site's Catalog only documents `values.yaml`.** It does not ingest `terraform/<module>/README.md` or `kustomize/<add-on>/README.md` into any page of its own — those READMEs stay this repo's reference, readable directly on GitHub. A Catalog guide (`docs/guides/<name>.md` in this repo, vendored to `/catalog/core/guides/<name>` on the site) links out to the real GitHub path (`https://github.com/windsorcli/core/tree/main/<terraform|kustomize>/<path>`) rather than the site hosting a mirrored copy. Author and generate the per-module/stack READMEs exactly as described below regardless — they're still the real reference, just not republished.

**Editorial split:** `/docs/blueprints/*` on the site = Blueprint API, schema, facets for **any** author. A Catalog guide here = a values.yaml-facing walkthrough for **this** blueprint's own config surface, diagram-first, linking to GitHub for anything deeper than the knob itself.

## Frontmatter (Markdown)

- `title` (required), `description` (**required for per-module READMEs** — the umbrella generator pulls from it; missing descriptions fail CI).
- Optional: `sidebar_order` for ingest nav.

## Voice

- **Reference only:** imperative, tables for inputs/vars, no marketing copy.
- Link generic blueprint concepts to `https://www.windsorcli.dev/docs/blueprints/...` (schema, sharing, facets).

## Catalog guides (`docs/guides/`)

A Catalog guide is `docs/guides/<key>.md`, vendored to `/catalog/core/guides/<key>` on the site. Write the intro, diagram, and "Under the hood" prose by hand — `scripts/guide-scaffold.sh` only ever fills in one thing: the `## Reference` block, a list of every `terraform/` and `kustomize/` path the facets actually wire in for that guide's config key, derived from the real facet YAML rather than typed by hand and left to drift.

Add a `<!-- BEGIN_GUIDE_REFS -->` / `<!-- END_GUIDE_REFS -->` marker pair wherever the generated list should go, then run `task docs:guides` (or target one guide directly: `scripts/guide-scaffold.sh <key>`). `task docs:guides:check` fails on drift — wired into CI the same way `docs:kustomize:check`/`docs:terraform:check` are. The generator only ever populates an existing file; it doesn't scaffold one, so the marker pair (and everything above it) has to exist first.

**Vendor sub-guides.** When a schema key has more than one driver — `database.postgres.driver: cloudnativepg | rds | azuredb | cloudsql`, `identity.driver: keycloak | oidc` — split the guide into `docs/guides/<key>/<vendor>.md`, one file per enum value, filename matching the schema value verbatim (`azuredb.md`, not `flexibleserver.md`). There's no separate index page for the category; the site groups these into one expandable sidebar entry per key automatically. Generate with `scripts/guide-scaffold.sh <key>/<vendor>` (or `--all` picks up every vendor page that already exists). A driver with nothing to reference (an external service Windsor installs nothing for, e.g. `identity/oidc.md`) still needs the marker pair — an intentionally empty generated block is what lets `--check` catch it if that ever stops being true, and says so in the surrounding prose rather than silently having no `## Reference` section at all.

## Umbrella indices (`kustomize/README.md`, `terraform/README.md`)

Both umbrella READMEs carry a `<!-- BEGIN_INDEX -->` / `<!-- END_INDEX -->` region populated by `scripts/umbrella-index.sh <root>`. The generator is bundled into the existing per-layer doc tasks: `task docs:kustomize` runs the kustomize index after the add-on tables, `task docs:terraform` runs the terraform index after terraform-docs. CI catches drift via `task docs:kustomize:check` and `task docs:terraform:check` — there is no standalone umbrella task. The generator walks each per-module README (kustomize 1-level-deep; terraform any depth, skipping `.terraform/`), pulls the frontmatter `description:`, and emits a `| path | purpose |` table; missing `description:` fields fail the build.

The umbrellas exist purely as **reference indices** for browsing this repo on GitHub. Don't put system overviews, decision matrices, or architecture diagrams in them — that content belongs in a Catalog guide on the site instead.

## Terraform reference

- Generate from modules in this repo with `task docs:terraform` (terraform-docs injected between `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers in each module's `README.md`). Commit the regenerated `terraform/<module-path>/README.md` (`cluster/talos`, `gitops/flux`, etc.). CI runs `task docs:terraform:check` to fail on drift. The site doesn't ingest these — link to `https://github.com/windsorcli/core/tree/main/terraform/<module-path>` from a Catalog guide instead.
- Inputs, outputs, and gotchas belong here; high-level "what is Terraform in Windsor" stays on the site under `/docs/components/terraform`.

## Kustomize add-on README (per `kustomize/<add-on>/`)

Each add-on gets one `kustomize/<add-on>/README.md` plus one `kustomize/<add-on>/.docs.yaml` descriptor. The README is hand-authored; the Substitutions / Components / Dependencies tables are generated from the descriptor by `scripts/kustomize-docs.sh` (wired through `task docs:kustomize`) and live between `<!-- BEGIN_KUSTOMIZE_DOCS -->` / `<!-- END_KUSTOMIZE_DOCS -->` markers. CI runs `task docs:kustomize:check` to fail on drift.

Fixed section order (target ~120 lines):

```
2-sentence lede
## Architecture       single Mermaid (sane-default config) + 2-4 interpretive sentences
## Recipes            terse YAML per variant, one-line header per recipe
## Operations         bulleted "if X then Y" failure modes
## Security           2-4 bullets (PSA, capabilities, secret handling)
<!-- BEGIN_KUSTOMIZE_DOCS -->
generated tables                                  # never hand-edit
<!-- END_KUSTOMIZE_DOCS -->
## See also           cross-links
```

Diagram conventions: architecture (static structure), not flow. One diagram per add-on showing the sane-default config; variants live in Recipes, not in extra diagrams. LR direction, namespace subgraphs always shown, nodes labeled by kind (`HelmRelease cilium`, not `cilium`), no color.

`.docs.yaml` shape (kept single-line — Markdown tables don't render multi-line cells without `<br/>`):

```yaml
substitutions:
  <name>:
    required_when: <string>         # default "always"
    description: "<single line>"

components:
  <name>:
    enable_when: <string>           # default "always"
    description: "<single line>"

dependencies:
  <add-on>:
    required_when: <string>         # default "always"
    reason: "<single line>"
```

Reference: [kustomize/cni/](../../../kustomize/cni/) is the single-facet pilot — copy its `README.md` + `.docs.yaml` pair as a template when authoring a new add-on. Align with `.claude/skills/kustomize-author/SKILL.md` for the underlying Kustomize layout.

### Multi-facet add-ons (`base+resources` split)

Some add-ons split into two Kustomization paths so Flux reconciles CRDs / Helm releases (`<addon>/base`) before the resource CRs that depend on them (`<addon>/resources`). Facets are named `<addon>-base` and `<addon>-resources`; the latter `dependsOn` the former. Active examples: `policy`, `pki`, `telemetry`, `gateway`, `lb`.

`.docs.yaml` adds a top-level `facets:` list and tags each component with its `facet:`:

```yaml
facets:
  - <addon>-base
  - <addon>-resources

components:
  <name>:
    facet: <addon>-base
    enable_when: <string>
    description: "<single line>"
```

`scripts/kustomize-docs.sh` renders one `## Components — <facet>` sub-table per facet in declared order. The safety check fails closed on components missing `facet:` or referencing a facet not in the list.

Collision rule: when the same literal name is wired in both facets (e.g. `prometheus` lives in `telemetry-base` as the Helm release and in `telemetry-resources` as ServiceMonitors), use path-prefixed keys in `.docs.yaml` — `base/prometheus`, `resources/prometheus`. Operators still write the bare name in their facets; the path resolves from the facet's `path:`. Call this out in the README intro whenever prefixes appear.

Reference: [kustomize/policy/](../../../kustomize/policy/) is the simplest multi-facet pilot; [kustomize/telemetry/](../../../kustomize/telemetry/) shows the collision-prefix case.

## Compatibility

- Keep a single **blueprint-scoped** matrix (CLI minimum, Kubernetes, Flux) in `docs/compatibility.md` (or equivalent)—“running **this** blueprint,” not generic Windsor marketing.

## PR checklist

- [ ] Module or stack behavior that affects operators reflected in the relevant per-module/stack `README.md`.
- [ ] Generated Terraform docs refreshed if inputs/outputs changed.
- [ ] Catalog guide `## Reference` blocks refreshed (`task docs:guides`) if a facet's `terraform:`/`kustomize:` wiring changed.
- [ ] Links to Blueprint schema/facets point at windsorcli.dev `/docs/blueprints/...`, not duplicate prose.
- [ ] No slug or path that implies generic blueprint authoring—that belongs on the website repo.

## Internal architecture note

[windsorcli.github.io `docs/plan.md` on GitHub](https://github.com/windsorcli/windsorcli.github.io/blob/main/docs/plan.md) — maintainer planning only; not published on windsorcli.dev.
