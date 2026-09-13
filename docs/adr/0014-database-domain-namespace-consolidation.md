---
title: "ADR-0014: Database domain and namespace consolidation"
description: Moves everything database-specific out of kustomize/provisioning (ProviderConfig, tag policies, monitoring, app-role) into kustomize/database, and out of system-provisioning into system-database — so any postgres driver's own infrastructure lives in one namespace and one domain, regardless of which one is active. Revises ADR-0009 §2's original domain placement.
---

# ADR-0014: Database domain and namespace consolidation

## Status

Proposed, implemented alongside [ADR-0013](0013-declarative-app-role-provider-sql.md)
on `feat/provider-sql-app-role`. Revises [ADR-0009](0009-crossplane-cloud-databases.md)
§2's domain placement. Not yet verified live.

## Context

`database.postgres.driver` selects exactly one of four values —
`cloudnativepg`, `rds`, `flexibleserver`, `cloudsql` — never more than one
active per context. Before this ADR, the `cloudnativepg` driver's
operator ran in `system-database`; the other three ran their entire
apparatus (Crossplane engine, `ProviderConfig`, tag policies, monitoring,
app-role) in `system-provisioning`, a namespace named for the mechanism
(Crossplane), not the capability (Postgres).

Debugging the 2026-09-08 Azure acceptance failure that led to ADR-0013
surfaced this split as a real cost, not a theoretical one: "check
`system-database` for anything Postgres-related" is the natural first
move for anyone operating this repo, and it's wrong for three of the four
drivers. Two facts, checked directly rather than assumed, removed any
reason to keep the split:

- `kustomize/database/install/namespace.yaml` and
  `kustomize/provisioning/install/namespace.yaml` are byte-identical
  except the `name:` field — same PSA labels
  (`baseline`/`baseline`/`baseline`) on all three axes. No policy reason
  they were ever two namespaces.
- They already never coexist: `database`'s Flux entry gates on
  `driver == 'cloudnativepg'`, `provisioning`'s on the other three —
  mutually exclusive by construction, since `driver` is one enum value.

Separately, a Kyverno policy's *source* directory was already established
as decoupled from its *runtime* namespace in this codebase —
`kustomize/pki/resources/private-issuer/ca/kyverno-inject/inject-private-ca-policy.yaml`
mutates `Pod`s cluster-wide by label, with no `system-pki` scoping at all
— removing "moving the source files changes nothing about lifecycle
pairing" as an objection on its own.

## Decision

### 1. `kustomize/provisioning` narrows to generic Crossplane mechanics only

`kustomize/provisioning/install/crossplane/` (the Helm release) and
`install/crossplane/{aws-rds,azure-postgres,gcp-cloudsql,provider-sql}/`
(each driver's `Provider` CR + `DeploymentRuntimeConfig`) are all that
remain. These bind the Crossplane *provider pods themselves* — which need
their own cloud IAM identity to call AWS/Azure/GCP APIs and manage the
actual cloud resources — and stay in `system-provisioning` regardless of
this ADR. Nothing here is database-specific; a future non-Postgres
Crossplane-backed capability (S3, say) would extend this tier the same
way, exactly the forward-compatibility ADR-0009 §2 argued for
originally. That argument was right; it just didn't yet distinguish the
engine from what it's used for.

### 2. `kustomize/database/resources/crossplane/` gets everything that's actually database-specific

Moved wholesale from `kustomize/provisioning/resources/crossplane/`:
`ProviderConfig` (admin), tag/resource-group/project policies,
monitoring `ClusterPolicy`s and their RBAC, `monitoring-exporter/`, and
`app-role/` (ADR-0013's `Role`/`Database`/connection-secret mechanism).
Every `namespace: system-provisioning` in these files becomes
`namespace: system-database`; `kustomize/postgresql-app-role`'s directory
moved alongside them, one level up (`database/resources/crossplane/postgresql-app-role`),
since it's referenced identically by all three drivers' `app-role`
components.

### 3. A `database`-named Flux entry per driver, `install: components: []`

The `database` Flux entry (facet name, not domain path) already exists
for `cloudnativepg`; this ADR adds three siblings, one per
Crossplane-backed driver, mutually exclusive by the same `when:` pattern
`provisioning`/`provisioning-providers` already established for having
multiple entries share one name. Each carries the moved `resources:`
block (unchanged in shape — same `dependsOn: [provisioning-providers-install]`,
same substitutions, same driver-specific `components:` — only the
`path:` target changed) plus a minimal `install: { components: [] }`.

That empty `install:` isn't a no-op. Confirmed directly from the CLI's
own compiler
(`cli/pkg/provisioner/flux/stack.go:runFromScratch`/`writeSyntheticKustomization`):
when a system's `install.components` is empty and its base directory
isn't itself a Kustomize `Component` (true for every domain's
`install/kustomization.yaml`, which is a plain `Kustomization`, not a
`Component`), the compiler runs `kustomize build` directly against that
base directory instead of synthesizing a components-wrapper. Since
`kustomize/database/install/kustomization.yaml` is `resources:
[namespace.yaml]` unconditionally, this renders exactly the namespace —
nothing else — regardless of what (if anything) gets appended to
`components:`. This is what guarantees `system-database` exists for the
`rds`/`flexibleserver`/`cloudsql` drivers, which previously had no
`install:`-bearing entry at `path: database` at all.

The blueprint-test framework's `expect.flux[].install` matcher doesn't
handle this specific shape (`components: []` alone) — asserting it
returned "expected present, got absent" even though the described CLI
behavior confirms the render is correct. Tests assert the `resources:`
tier only for these entries; the `install:` behavior is verified against
the CLI's own source, not the test DSL.

### 4. `demo`'s and `demo-app-role`'s `dependsOn`/`path` follow the move

`option-demo.yaml`'s three driver-specific `demo` entries depended on
`provisioning-resources`, which no longer exists as a name (the
`resources:` tier that rendered it moved to the `database`-named entries,
which render as `database-resources` — the standard `<name>-resources`
convention, unaffected by the rename since `database` was already a name
in use, just for a different driver each time). Updated to
`dependsOn: [database-resources]`. The three `demo-app-role` entries'
`path: provisioning` becomes `path: database`, matching where
`crossplane/{aws-rds,azure-postgres,gcp-cloudsql}/app-role` now live.

### 5. Terraform: only the identities that actually move

Checked precisely rather than assumed, since a `(namespace, service_account)`
pair is the literal trust-policy subject for Pod Identity/Workload
Identity federation, not just a label:

- `terraform/provisioning/crossplane-iam`, `crossplane-identity-azure`,
  `crossplane-identity-gcp` bind the Crossplane **provider pods**
  (`provider-aws-rds`, `provider-azure-dbforpostgresql`, `provider-gcp-sql`)
  — these stay in `system-provisioning` per Decision §1, so these three
  modules are **unchanged**.
- `terraform/database/aws-rds`'s `aws_eks_pod_identity_association.secret_reader`
  binds the **app-role bootstrap identity** (`rds-secret-reader`), the
  only one of the three bootstrap ServiceAccounts with real cloud IAM
  federation (it calls `secretsmanager:GetSecretValue`; the azure/gcp
  bootstrap identities have no cloud API access at all — confirmed by
  grep, zero Terraform references to `flexibleserver-bootstrap`/
  `cloudsql-bootstrap` anywhere). `namespace = "system-provisioning"` →
  `"system-database"`.
- `terraform/database/gcp-cloudsql`'s `kubernetes_namespace_v1` (it
  pre-creates the namespace because Terraform runs before Flux and needs
  somewhere to write the admin-credentials Secret, the same
  Terraform-runs-first pattern `cluster/aws-eks/additions`'s `system-dns`
  and `gitops/flux`'s `flux-system` already use) is renamed
  `system_database`, targeting `system-database`.
- Both modules' `test.tftest.hcl` updated to match and re-run clean.

### 6. Deduplicated the driver-parity boilerplate this move made visible

Moving all three drivers' files into one parent directory surfaced how
much of `kyverno-background-controller-rbac.yaml`, `monitoring-rbac-policy.yaml`,
and `app-role/rbac.yaml` was byte-identical across drivers, differing only
in a CRD's `apiGroup`/resource name and a handful of resource names —
confirmed with `diff`, not assumed. `kyverno-background-controller-rbac.yaml`
and `app-role/rbac.yaml` moved into shared, substitution-parameterized
templates (`crossplane/monitor-generate-rbac` and `crossplane/postgresql-app-role`
respectively — the same treatment ADR-0013 already gave `Role`/`Database`),
cutting the duplicate content to one copy plus three small substitution
blocks each.

`monitoring-rbac-policy.yaml` and `tag-policy.yaml`/`resourcegroup-policy.yaml`/
`project-policy.yaml` were checked the same way and left alone:
`monitoring-rbac-policy.yaml`'s `match.resources.kinds` needs three list
entries for `rds.aws.upbound.io` (one per historical API version) but one
for the other two drivers — Flux substitution has no array primitive,
and stuffing a multi-line list into one substitution value is exactly the
"corrupts the surrounding YAML block scalar" failure mode already
documented elsewhere in this repo (`app-role`'s old `pg_grant_sql`
comment). The tag/resource-group/project policies each patch a genuinely
different field per cloud — not the same template with different values.

A later pass (prompted by a direct question — "is this duplication
actually required?" — not found independently) checked `provider-config.yaml`
and each driver's `connection-secret-cronjob.yaml` the same way and found
both genuinely convergent after all:

- **`provider-config.yaml`** was identical across all three drivers
  except one word in a comment (the CRD kind name). Folded into
  `postgresql-app-role/provider-config.yaml`, parameterized by the same
  `pg_crd_kind` this section's `monitoring-cronjob-policy.yaml` fix
  already introduced.
- **`connection-secret-cronjob.yaml`** converged once ADR-0015 put aws-rds
  on the same admin-secret mechanism as azure-postgres: both read a
  single Kubernetes Secret for the password and a CRD field for the
  endpoint, differing only in the CRD reference, the endpoint's field
  name, and where the username lives. gcp-cloudsql's admin username has
  no CR-level field at all — Cloud SQL's admin user is a separate `User`
  resource, not an instance-level field the way RDS/FlexibleServer expose
  one — so it reads username from the same Secret as password, a real
  structural difference, not a stylistic one. Unified into one script
  with a `pg_username_from_secret` true/false substitution driving a
  plain bash `if`/`else` between "read `spec.forProvider.<pg_username_field>`
  from the instance CR" and "read `.data.<pg_username_field>` from the
  admin Secret" — both branches are literal text in the one shared file;
  substitution only picks which command actually runs.

One substitution-mechanics constraint drove that `if`/`else` design
rather than a single per-driver "fetch command" substitution: Flux's
`postBuild.substitute` is a single text-replace pass over the original
manifest text. A substitution value that itself contains another
`${variable}` reference (e.g. a `pg_username_cmd` value embedding
`${pg_instance_name}`) would never get that inner reference resolved —
it only existed after the outer substitution ran, too late for Flux's
one pass to see it. Keeping every `${variable}` reference literal in the
committed template, never inside another variable's value, avoided that
trap. Simulated all three drivers' full substitution locally (not just
`kustomize build`, which doesn't perform Flux's substitution step) to
confirm zero unresolved placeholders and valid bash (`bash -n`,
`shellcheck`) for each rendered script before trusting the design.

With both files converged, the per-driver `app-role/` subdirectories
(`aws-rds/app-role/`, `azure-postgres/app-role/`, `gcp-cloudsql/app-role/`)
had nothing left in them — every file they held had moved into
`postgresql-app-role/`. Deleted; `option-demo.yaml`'s three `demo-app-role`
Flux entries reference `crossplane/postgresql-app-role` directly. The
`pg_provider_config` substitution also dropped out entirely: every
driver computed it identically as `provider-sql-${pg_instance_name}`, so
`role.yaml`/`database.yaml`/`provider-config.yaml` reference that pattern
directly now instead of routing it through a substitution that never
varied.

## Consequences

- An operator debugging any Postgres driver now checks one namespace,
  `system-database`, regardless of which one is active.
- `system-provisioning` is now genuinely generic — only Crossplane's own
  engine and provider pods, nothing capability-specific — matching what
  ADR-0009 §2 argued the domain should be, now actually true of its
  contents.
- This is a resource rename for the `gcp-cloudsql` driver's Terraform
  state (`kubernetes_namespace_v1.system_provisioning` → `system_database`)
  and the `rds` driver's Pod Identity association's `namespace` attribute
  — a destroy/recreate on `apply`, not an in-place update, and no
  `moved {}` block was added. Consistent with this exact codebase's own
  precedent for pre-adoption restructuring (ADR-0009's Consequences:
  "Safe here because none of the five carry a lifecycle of their own... That
  won't stay true forever") — this mechanism has no real deployments yet.
- Blueprint composition (`task test:blueprint`, 359 cases) and both
  affected Terraform modules' test suites (`task test:terraform`) pass.
  `kustomize build` was run directly against every moved directory to
  confirm no reference breakage; the `install: components: []` behavior
  is verified against CLI source, not a live apply.

## Alternatives considered

**Leave the split, improve documentation instead.** Doesn't fix the
actual failure mode — an operator's first instinct under time pressure is
still to check the wrong namespace. The two namespaces being
byte-identical in PSA posture and never coexisting removed any real
reason to keep them separate.

**Move only the kustomize directory, keep the Kubernetes namespace as
`system-provisioning`.** Considered given the Kyverno precedent that
source location and runtime namespace are already decoupled in this
codebase. Rejected because the actual operator-facing problem is the
namespace, not the file tree — moving only the tree keeps the
discoverability gap that motivated this ADR in the first place.

**Move CNPG's operator into `system-provisioning` instead, treating
"provisioning" as the umbrella for all database mechanics.** Rejected:
Crossplane's provider pods are cloud-API-calling, cluster-IAM-bound
identities with no relationship to CNPG's own in-cluster operator, and
folding CNPG in would make `system-provisioning` mean two unrelated
things (a generic engine namespace and a specific operator's namespace)
instead of one.

## References

- [ADR-0009](0009-crossplane-cloud-databases.md) §2 — the original
  `provisioning`, not `database`, domain placement this ADR revises.
- [ADR-0013](0013-declarative-app-role-provider-sql.md) — the app-role
  mechanism whose files moved as part of this same restructuring.
- `cli/pkg/provisioner/flux/stack.go` (`runFromScratch`,
  `writeSyntheticKustomization`, `isKustomizeComponent`) — the compiler
  behavior Decision §3's `install: components: []` relies on.
- `kustomize/pki/resources/private-issuer/ca/kyverno-inject/inject-private-ca-policy.yaml`
  — the existing precedent that a Kyverno policy's source directory and
  target namespace are independent.
