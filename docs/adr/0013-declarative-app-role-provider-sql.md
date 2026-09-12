---
title: "ADR-0013: Declarative app-role credentials via provider-sql"
description: Replaces the per-driver CronJob/bash mechanism ADR-0009 §7 built for provisioning a chart's app-role Postgres credential, and §8's monitor-role CronJob, with crossplane-contrib/provider-sql's declarative Role/Database/Grant resources, across rds, flexibleserver, and cloudsql. Admin credentials, networking, and IAM are unchanged.
---

# ADR-0013: Declarative app-role credentials via provider-sql

## Status

Proposed, implemented on `feat/provider-sql-app-role`. Supersedes
[ADR-0009](0009-crossplane-cloud-databases.md) §7 and §8, and the
equivalent mechanism [ADR-0011](0011-crossplane-azure-flexible-server.md)
carried forward for `flexibleserver`, plus the same shape's undocumented
third copy for `cloudsql`. Verified live for app-role; see Verification
needed below for what's still outstanding on monitor-role.

## Context

A `windsor` acceptance run against `azure` failed on 2026-09-08: the
`Setup` step hung until CI's 30-minute timeout, waiting on the
`demo-app-role-resources` Kustomization, which never went Ready.

The support bundle traced it to a lost race. `demo-db-provision-app-role-initial`,
the one-shot Job ADR-0009 §7 added specifically to "ensure this ran once
reliably," ran three attempts within 35 seconds and exhausted
`backoffLimit: 2` — every attempt failed instantly, not on a timeout,
because the admin credential Secret the provider auto-generates for
`FlexibleServer` hadn't been written yet on the reconcile immediately
following `Ready`. The `demo-app-role-resources` Kustomization's
`healthCheckExprs` gated on that one Job's `Complete` condition, and a
failed Job never re-runs on its own. The CronJob ADR-0009 §7 also installs
kept retrying every 5 minutes and would have succeeded eventually. Flux
was never watching it, only the dead Job, which had no way to report
success again. The Kustomization was stuck, not slow.

An interim fix (`fix/app-role-secret-race-healthcheck`, not this branch)
made `fetch-admin-credentials.sh` poll instead of failing on the first
miss, and moved `healthCheckExprs` to gate on the CronJob's own
`status.lastSuccessfulTime`. That fix stands on its own, but it exposed
the deeper question this ADR answers: once health no longer depends on a
one-shot Job succeeding, the whole hand-rolled mechanism — three drivers
independently reimplementing idempotent role creation, password
generation, and credential publishing in bash — stops earning its
complexity.

ADR-0009 §7 considered `provider-sql` and rejected it: "Rather than wait
on [External Secrets Operator], or bring in a second Crossplane provider
(`provider-sql`) that would still need the same runtime-secret bridge for
its own `ProviderConfig`, this ADR adds a purpose-built CronJob." That
reasoning holds for AWS, where the admin credential lives in Secrets
Manager, not a Kubernetes Secret. It doesn't generalize as written: Azure's
`FlexibleServer` already auto-generates its admin password directly into a
Kubernetes Secret, and GCP's Terraform module already writes one — but (see
Decision §3) even those two still need a small bridge, just a smaller one
than AWS's, to combine that Secret with the instance's own endpoint into
the one Secret `provider-sql`'s `ProviderConfig` reads.

## Decision

### 1. Install `crossplane-contrib/provider-sql`, once per context, alongside the existing per-cloud providers

Verified against the provider's source (crossplane-contrib org, Apache-2.0,
154 stars, actively releasing — latest `v0.14.0` added Crossplane v2
support, matching the `v2` split (`apis/cluster/...` vs `apis/namespaced/...`)
this repo's own vendored `crossplane-2.4.0` CRDs already assume) and
published to `xpkg.upbound.io/crossplane-contrib/provider-sql`, digest
resolved directly against the registry (`crane digest`), not guessed —
`v0.14.0@sha256:d14af351...`. `kustomize/provisioning/install/crossplane/provider-sql/`
follows the same three-file shape `aws-rds`/`azure-postgres`/`gcp-cloudsql`
already use, minus a family-provider dependency (`provider-sql` is
hand-written, not upjet-generated from a Terraform provider). Its
`DeploymentRuntimeConfig` sets `resources.requests/limits` — the other
three providers' don't, relying on the `resource-limits-requests` Kyverno
policy being `Audit` rather than `Enforce`; `provider-sql`'s doesn't carry
that gap forward. Referenced from each driver's own `provisioning-providers`
Flux entry (`addon-database.yaml`), so it installs once whichever cloud
driver is active, and its `Role`/`Database` CRDs work identically against
RDS, FlexibleServer, and Cloud SQL — they speak the Postgres wire protocol,
not a cloud API.

### 2. `kustomize/database/resources/crossplane/postgresql-app-role/` — the one piece that's genuinely identical across drivers

A plain, ordinarily-named Component (`role.yaml`, `database.yaml`), not
tucked under a `_shared/`-prefixed directory the way the bash scripts it
replaces were. That prefix existed for exactly one reason — merging
literal script text from multiple `configMapGenerator`s into one
`/scripts` mount via a projected volume — and it's the only directory in
the entire `kustomize/` tree that ever used it. Once the scripts are gone,
so is the reason; a Component referenced by relative path from the three
drivers' Flux entries is the same everyday mechanism this repo already
uses everywhere else (`database`, `database/rds`, and every other
multiply-referenced Component), not a new device. (A later pass folded
`ProviderConfig`, the CronJob, and the RBAC in here too, once it turned
out those converged as well — see the follow-up dedup note in
[ADR-0014](0014-database-domain-namespace-consolidation.md) §6.)

- **`Role`** (confirmed from `role_types.go`): `PasswordSecretRef` is
  optional — "If no reference is given, a password will be
  auto-generated." Confirmed from `postgresql.go`'s
  `GetConnectionDetails`: the controller publishes `username`/`password`/
  `endpoint`/`port` to `writeConnectionSecretToRef`. Pointed at the
  chart's own namespace, this replaces the old `write-app-password.sh`
  *and* `publish-app-secret.sh` outright — no `/dev/urandom`, no
  `kubectl create secret --dry-run=client | kubectl apply`, no separate
  step. `deletionPolicy: Orphan`, not the default `Delete`: the `Database`
  below makes this role own its database, and PostgreSQL refuses
  `DROP ROLE` on a role that still owns objects — `Delete` would leave a
  disabled Kustomization's prune permanently stuck.
- **`Database`** (confirmed from `database_types.go`): `Owner`/`OwnerRef`
  maps straight onto `ALTER DATABASE ... OWNER TO`, the exact statement
  `provision-app-role.sh` ran by hand. The database itself already exists
  — each driver's own instance component creates it — so this object
  adopts it by name via `ownerRef` rather than creating a second one, the
  same adopt-in-place behavior every Crossplane MR uses for a
  pre-existing external resource. Also `deletionPolicy: Orphan`, so
  disabling app-role never drops the chart's actual data.
- **No `Grant` template.** `pg_grant_sql`'s old role (one line,
  semicolon-separated SQL, for whatever ownership doesn't cover) has no
  clean structured equivalent worth templating — nothing in this repo
  uses it non-empty today. A chart that needs one adds its own
  `postgresql.sql.crossplane.io Grant` referencing `<pg_database_name>-app`
  by name, the same posture ADR-0009 §4 already takes for the instance CR
  itself: the chart creates Crossplane's native resource directly, no
  core abstraction.

### 3. Per-driver, per-instance `ProviderConfig` + a small connection-secret mirror — the piece that's genuinely different

`provider-sql`'s `ProviderConfig` (confirmed from `provider_types.go`)
supports exactly one credentials source, `PostgreSQLConnectionSecret`: one
Secret with `endpoint`/`port`/`username`/`password` keys. Named
`provider-sql-${pg_instance_name}` — per instance, not per driver, since a
context could plausibly have more than one FlexibleServer/Instance/
DatabaseInstance, each needing its own connection Secret.

No existing mechanism assembles that Secret. Each driver's admin
credential is real, but never already in the exact 4-key form
`provider-sql` needs:

- **azure-postgres**: `<name>-admin-credentials` (provider-generated)
  carries `password` only; `endpoint` and `administratorLogin` live on the
  `FlexibleServer` CR itself, not the Secret.
- **gcp-cloudsql**: `<name>-admin-credentials` (Terraform-written) already
  carries `username`+`password`; `endpoint` lives on the `DatabaseInstance`
  CR's `status.atProvider.privateIpAddress`.
- **aws-rds**: at the time this ADR was written, the master credential
  lived in AWS Secrets Manager, not a Kubernetes Secret at all — the one
  genuine "different system" bridge ADR-0009 §7 originally built for.
  [ADR-0015](0015-rds-autogenerate-admin-password.md) later replaced that
  with the same `autoGeneratePassword`/`passwordSecretRef` mechanism
  azure-postgres already uses below, closing this asymmetry.

Each driver's connection-secret-mirror CronJob does exactly this
one job, every 5 minutes: read the instance CR (skip cleanly if not
`Ready`), read whatever admin credential already exists in its own
Kubernetes Secret (skip cleanly if not yet populated), and `kubectl apply`
the merged
`<name>-connection` Secret. No DDL, no password generation, no
multi-container handoff — one container, ~40 lines, using the same
`flexibleserver-bootstrap`/`cloudsql-bootstrap`/`rds-secret-reader`
identities and RBAC the old mechanism already had — all three drivers'
existing Secret read/write Roles already covered a new Secret name, no
permission widening needed (see [ADR-0014](0014-database-domain-namespace-consolidation.md)
for where these identities and their RBAC actually live now).

**A Kyverno `generate` policy was considered and rejected for azure/gcp,
even though it looked cleaner at first** — Kyverno's `context: apiCall`
could read the admin Secret and its `generate` rule could write the merged
one, avoiding a CronJob entirely for two of three drivers. Rejected once
the RBAC it would need was worked out concretely: Kyverno's
background-controller only gets access to a resource kind by an
explicitly aggregated `ClusterRole` (this repo's own existing pattern, see
`kyverno-background-controller-rbac.yaml` in each driver), and RBAC
`resourceNames` can't scope a `create` (there's no name to check yet). The
grant would have to be cluster-wide `get`/`list`/`create`/`update`/`delete`
on `secrets` for Kyverno's own controller — every Secret in every
namespace, not just the two this actually needs — a much bigger
expansion of Kyverno's own blast radius than the narrowly-scoped,
namespace-local RBAC a small CronJob needs. Keeping one uniform mechanism
across all three drivers, even though azure/gcp's version is nearly all
boilerplate, was worth more than saving two small CronJobs at that cost.

### 4. `healthCheckExprs` gates on `Role`'s own `Synced` condition

No Job, no CronJob, no `lastSuccessfulTime` polling window — an ordinary
Crossplane MR's `Synced` condition, the same pattern every other
`healthCheckExprs` entry in `option-demo.yaml` already uses for the
instance CRs themselves. If the connection Secret isn't populated yet,
`provider-sql`'s own reconciler reports `ReconcileError` and retries on
its own schedule — the identical self-healing behavior already observed
live on `FlexibleServerDatabase` racing `FlexibleServer`'s own readiness
(`"cannot resolve references: ... referenced resource may not yet be
ready"`, self-resolving on the next reconcile). Kustomization `timeout`
moved 5m → 10m to give the connection-secret CronJob's own 5-minute
schedule room inside one reconcile attempt without cycling through a
"not ready" state every time.

## What's unchanged

- **Admin/master credential provisioning** — still whatever each driver
  already does. This ADR only changes what reads that credential and how
  the *application* credential gets derived from it.
- **IAM, security groups, KMS, subnet wiring** — ADR-0009 §3, §6
  unchanged.
- **Monitoring's `postgres_exporter` Deployment/Service/PodMonitor** —
  still ADR-0009 §8's Kyverno `generate` policy. What changed: the
  `monitor` role itself moves off that section's CronJob onto the same
  model as the application credential — a `crossplane/postgres/monitor-role`
  component (a `Role` granted `pg_monitor` via a `Grant`), sharing
  `instance-connection`'s `ProviderConfig`/`WatchOperation` with
  `app-role` rather than duplicating it. `postgres_exporter` reads the
  `Role`'s own `writeConnectionSecretToRef` Secret
  (`username`/`password`/`endpoint`/`port`) instead of a CronJob-composed
  `uri`.

## Verification needed before merge

**app-role**: source-verified against `provider-sql`'s own code,
validated with `kustomize build` against every changed component, and
confirmed against a live cluster for all three backends (full
`windsor bootstrap` on aws-test, azure-test, and gcp-test).

- **`Role`/`Database` `Ready`/`Synced` semantics under `healthCheckExprs`**
  — confirmed live on all three: the `Role`'s `Synced` condition gated
  `database-resources` as expected.
- **`sslMode: require`** — confirmed live on all three: `provider-sql`
  connected to each backend over TLS with no CA bundle sourced.
- **Connection reachability** — confirmed live on all three:
  `provider-sql`'s own provider pod reached each VPC-private instance
  directly.

**monitor-role**: source-verified against `provider-sql`'s `Grant` CRD
and validated with `kustomize build`; not yet verified against a live
cluster.

- **`Grant`'s `role`/`memberOf` fields** — confirmed against
  `provider-sql`'s CRD schema directly (`role`: the grantee; `memberOf`:
  the role granted), not yet confirmed that Postgres accepts the
  generated `GRANT pg_monitor TO <role>` live.
- **`postgres_exporter`'s `DATA_SOURCE_URI`/`DATA_SOURCE_USER`/
  `DATA_SOURCE_PASS` env vars** — Kubernetes' own interdependent-env-var
  expansion, not yet confirmed that `postgres_exporter` v0.20.1 parses
  the resulting DSN correctly live.
- **`instance-connection` shared by two components** — validated that
  `app-role` and `monitor-role` both referencing it in one Kustomization
  doesn't duplicate the `ProviderConfig`/`WatchOperation` (`kustomize
  build` only), not yet confirmed Crossplane reconciles the shared
  `ProviderConfig` correctly when both consumers are present live.
## Alternatives considered

**Keep the CronJob, patched.** The interim fix (polling, health-gate on
the CronJob) makes the current mechanism work, not fail silently forever.
Rejected as the long-term answer anyway: three drivers independently
reimplementing idempotent-role-creation-and-credential-publishing in bash
is the DRY failure this ADR closes, and a controller retrying a transient
reconcile error is a better fit for "wait for an eventually-consistent
secret" than a Job with a fixed retry budget ever was.

**`crossplane-contrib/provider-random` for password generation.**
Investigated and doesn't exist as a maintained package — the closest
match, `crossplane/crossplane#4436` ("add support for the hashicorp/random
provider"), is closed with no provider ever published under that name.
Moot regardless: `provider-sql`'s `Role` generates its own password when
`passwordSecretRef` is omitted.

**Kyverno `generate` for the azure/gcp connection-secret bridge.**
Covered in Decision §3 — rejected once the actual RBAC cost (cluster-wide
Secret access for Kyverno's own controller) was worked out, in favor of
one uniform, narrowly-scoped mechanism across all three drivers.

**A Composition/XRD abstracting the three drivers behind one claim CRD.**
Rejected for the same reason ADR-0009 §4 rejected a cross-cloud claim CRD
for the instance itself: no cross-cloud portability requirement exists
today, and `provider-sql`'s `Role`/`Database` are already cloud-agnostic
at the object level.

## References

- [ADR-0009](0009-crossplane-cloud-databases.md) §7 — the CronJob
  mechanism this ADR supersedes, and the `provider-sql` rejection this
  ADR revisits.
- [ADR-0011](0011-crossplane-azure-flexible-server.md) — carried §7's
  mechanism forward for `flexibleserver` unchanged.
- [ADR-0014](0014-database-domain-namespace-consolidation.md) — moved
  everything this ADR adds under `kustomize/provisioning/resources/`
  into `kustomize/database/resources/` and `system-provisioning` into
  `system-database`, decided and implemented alongside this ADR.
- [ADR-0015](0015-rds-autogenerate-admin-password.md) — replaced
  aws-rds's Secrets Manager admin credential with the same
  `autoGeneratePassword` mechanism azure-postgres already used here,
  simplifying the aws-rds connection-secret mirror to match.
- `crossplane-contrib/provider-sql`: [github.com/crossplane-contrib/provider-sql](https://github.com/crossplane-contrib/provider-sql),
  [marketplace.upbound.io/providers/crossplane-contrib/provider-sql](https://marketplace.upbound.io/providers/crossplane-contrib/provider-sql) —
  `apis/cluster/postgresql/v1alpha1/{role,database,grant,provider}_types.go`,
  `pkg/clients/postgresql/postgresql.go` are the specific files this ADR's
  Decision section cites.
- [crossplane/crossplane#4436](https://github.com/crossplane/crossplane/issues/4436) —
  closed, no `provider-random` ever shipped.
- `kustomize/database/resources/crossplane/postgresql-app-role/`,
  `kustomize/database/resources/crossplane/{aws-rds,azure-postgres,gcp-cloudsql}/app-role/`,
  `kustomize/provisioning/install/crossplane/provider-sql/` — the
  mechanism this ADR adds.
