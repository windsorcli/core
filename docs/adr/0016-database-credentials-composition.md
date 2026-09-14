---
title: "ADR-0016: DatabaseCredentials composition for chart self-service"
description: Introduces a Crossplane XRD/Composition, DatabaseCredentials, so a chart obtains a Postgres application credential against its own dedicated instance by creating one namespaced resource, instead of hand-authoring provider-sql's Role/ProviderConfig/connection-secret plumbing itself. Narrows, and does not re-litigate, ADR-0009 §4 and ADR-0013's rejection of a cross-cloud claim CRD.
---

# ADR-0016: DatabaseCredentials composition for chart self-service

## Status

Proposed, implemented on `feat/database-credentials-composition`. Migrates
`option-demo.yaml` fully onto `DatabaseCredentials` and deletes `app-role`,
`monitor-role`, and `instance-connection` — see Verification needed below
for what's still outstanding before this should be treated as confirmed
working.

## Context

ADR-0009 §4 established that a chart creates a cloud's own instance resource
directly — "no core-authored claim CRD or XRD... there's no cross-cloud
abstraction to preserve." ADR-0013 built app-role's Role/Database/Grant on
that same posture, and explicitly rejected a Composition/XRD wrapping the
three drivers: "no cross-cloud portability requirement exists today, and
provider-sql's Role/Database are already cloud-agnostic at the object
level."

Both rejections reasoned about *instance/driver portability*. Neither
addressed a different, later requirement: a chart that provisions its own
dedicated Postgres instance per environment — potentially several, across
different clouds — needs a repeatable way to turn "instance exists" into
"application has a working credential" without re-deriving, per instance,
which field on which upstream CRD holds the endpoint, which field holds
the admin username, and how to bridge that into provider-sql's
`ProviderConfig`. That bridge (`instance-connection`'s `WatchOperation`,
per ADR-0013) exists today, but only for the one instance `option-demo.yaml`
already names via Flux substitution — a chart provisioning its own instance
has no Flux substitution access to reuse it, and no reason to independently
learn three clouds' upstream field-naming conventions.

## Decision

### 1. `DatabaseCredentials` (`database.windsorcli.dev`, XRD scope
`Namespaced`) wraps the credential layer, not the instance layer

A chart creates its instance CR itself, exactly as ADR-0009 §4 already
requires. Once that instance is `Ready`, the chart creates one
`DatabaseCredentials` resource, in its own namespace, naming the driver and
the instance:

```yaml
apiVersion: database.windsorcli.dev/v1alpha1
kind: DatabaseCredentials
metadata:
  name: my-app-db
  namespace: my-app
spec:
  driver: rds
  instanceName: my-app-db
  databaseName: my_app
```

`driver` reuses `database.postgres.driver`'s exact vocabulary (`rds`,
`flexibleserver`, `cloudsql`) rather than asking the chart to supply an
apiVersion/kind pair or a raw field name — the same convention this
codebase already applies elsewhere, that vendor/engine identifiers are enum
values, never fields a consumer hand-derives. Everything driver-specific
(which CRD to watch, which field holds the endpoint, which field holds the
username, whether username comes from the admin secret) lives in a small
table inside the Composition — the same five facts `option-demo.yaml`'s own
ternary already encodes, relocated from a per-consumer Flux substitution
into one place no consumer ever sees.

### 2. One Composition per instance, not a shared credential-issuing
resource

Each `DatabaseCredentials` XR owns its own `ProviderConfig`, connection
Secret, and `Role` — all namespaced (`postgresql.sql.m.crossplane.io/v1alpha1`,
confirmed from the installed `provider-sql:v0.14.0` package's own CRDs, not
guessed), living in whatever namespace the XR itself was created in. This
is safe specifically because each XR's resources are independently owned:
two `DatabaseCredentials` XRs targeting the same instance (an app role and
a monitoring role, say) each get their own `ProviderConfig`/connection
Secret rather than fighting over one shared object. A namespaced XR
composing today's *cluster-scoped* `Role`/`Database` would never receive an
owner reference back (Kubernetes doesn't allow a cluster-scoped object to
be owned by a namespaced one) — the namespaced provider-sql API exists for
exactly this case.

No `Database`/ownership-reassignment step. That machinery (ADR-0013's
`Database` CR, adopting a database an admin already owns and reassigning
it) existed only because `app-role` needed to hand ownership from admin to
app role. `DatabaseCredentials`'s `Role` connects directly, with Postgres's
default `PUBLIC` `CONNECT` covering the common case. (Not yet verified
live — see Verification needed.)

### 3. `roleName`/`grants` generalize the XR beyond application credentials

`databaseName` is optional; `roleName` (defaulting to `<databaseName>-app`
when `databaseName` is set) and an optional `grants: [{memberOf: ...}]`
list cover roles that aren't "for" one database at all — a monitoring role
granted `pg_monitor`, for instance:

```yaml
spec:
  driver: rds
  instanceName: demo-db
  roleName: demo-db-monitor
  grants:
    - memberOf: pg_monitor
```

One `Grant` (also namespaced `postgresql.sql.m.crossplane.io`) is rendered
per list entry, `{role: <roleName>, memberOf: <entry>}`. This is what let
`option-demo.yaml` fully retire `app-role`, `monitor-role`, and
`instance-connection` rather than adding a fourth, narrower mechanism
alongside them — the demo now creates two `DatabaseCredentials` resources
(`demo-app`, `demo-db-monitor`) instead of assembling four components with
nine substitutions.

### 4. The admin-credentials Secret lives in `system-database`, by
convention, for every driver

`system-database` already holds `demo-db-admin-credentials` today. Every
driver's admin secret uses the same fixed location and naming
(`<instanceName>-admin-credentials`), because it removes any need for a
per-chart namespace to reach a cluster-scoped instance's admin credential:

- **RDS/FlexibleServer**: the chart points its own `passwordSecretRef`/
  `administratorPasswordSecretRef` at `{name: <instanceName>-admin-credentials,
  namespace: system-database}` — the provider's own controller generates
  and writes the password there, no new mechanism needed.
- **CloudSQL**: no equivalent auto-generate field exists on
  `sql.gcp.upbound.io` resources — see Decision §5.

The Composition fetches this Secret (a required-resource fetch by explicit
namespace, not a same-namespace-constrained managed-resource reference) and
merges it with the instance's live endpoint into a *new*, namespaced
connection Secret inside the chart's own namespace — satisfying the
namespaced `ProviderConfig`'s same-namespace-only `connectionSecretRef`.

### 5. A cluster-wide `WatchOperation` closes the GCP admin-credential gap

Today's GCP admin credential is Terraform-written (`terraform/database/gcp-cloudsql`),
reachable only from Core's own bootstrap — a third-party chart has no path
to invoke it. `provider-gcp-sql` has no `autoGeneratePassword` equivalent,
and `crossplane-contrib/provider-random` doesn't exist (confirmed, per
ADR-0013's own investigation).

A new, Core-installed `WatchOperation` watches `sql.gcp.upbound.io/v1beta2
DatabaseInstance` cluster-wide, unfiltered by name — unlike
`instance-connection`'s per-instance filtered watch. For every
`DatabaseInstance` it observes, it ensures
`<instance-name>-admin-credentials` exists in `system-database`,
generating a random password if not. A GCP chart gets this the moment it
creates its `DatabaseInstance`, with no manifest of its own — matching
RDS/FlexibleServer's native ergonomics instead of pushing the gap onto
every chart.

### 6. Lives under `kustomize/provisioning/resources/crossplane/`, not
`kustomize/database/resources/crossplane/`

`DatabaseCredentials` is domain-specific — ADR-0014 §2's stated home for
database-specific Crossplane resources. It's placed under `provisioning/`
instead because it has the same install-ordering dependency provider-sql
and function-python already have (the Composition references
`function-python`; both must exist before this XRD's Composition can
validate), and today's `provisioning` Flux entry is the one tier that
already sequences "engine, then provider-sql, then function-python."
Splitting it into `database/`'s own tier would need to re-derive that same
ordering a second time for no benefit. This is a deliberate exception to
ADR-0014 §2's split, not an oversight.

## What's unchanged

- Charts still create their instance CR directly — ADR-0009 §4 untouched.
- Charts still create their own database-creation CR where the cloud
  requires one (Azure's `FlexibleServerDatabase`, GCP's `Database`) — that
  stays driver-specific, at the same layer as creating the instance.
- `provider-sql`'s `Role`/`Database` semantics are unchanged. The namespaced
  API has no `deletionPolicy` field at all (confirmed live against the
  installed CRDs) — `managementPolicies` without `Delete` is its
  equivalent, and is what every composed `Role`/`Grant` here sets to guard
  against `Role.Delete()`'s known hang-on-unreachable-instance behavior.

## Verification needed before merge

Live-testing against a real `gcp-test` bring-up (cloudsql driver) surfaced
three bugs no amount of `kustomize build`/unit testing caught, all now
fixed:

- `req.observed.composite.resource` is a raw protobuf `Struct` — `[]` and
  `in` work, `.get()`/`.setdefault()` don't. Fixed by converting via
  `resource.struct_to_dict()` up front, matching what
  `request.get_required_resource()` already does internally.
- `rsp.desired.composite.resource` is the same kind of Struct wrapper on
  the output side — `.update()` works, `.setdefault()` doesn't.
- The namespaced `Role`/`Grant` CRDs have no `deletionPolicy` field at
  all — confirmed via `kubectl explain` against the live cluster.
  `managementPolicies` without `Delete` is the real equivalent.

Two more, once the app credential's `Role` actually started reconciling:

- Nothing auto-detects a composed resource's readiness from its own
  `status.conditions` — that's what the separate `function-auto-ready`
  function is for. Without it (or without checking manually), the XR's
  own `Ready` condition never flips even once every composed resource is
  genuinely healthy. Fixed by reading `req.observed.resources.get(name)`
  (its `.resource` extracted via `struct_to_dict()` first — the SDK's
  documented `get_condition(fnv1.Resource, ...)` path errored against the
  pinned `function-python:v0.2.0`, a likely version mismatch with the
  `main`-branch docs) and only marking `rsp.desired.resources[name].ready
  = True` once that resource's own `Ready` condition is `True`. Two
  resources have no `Ready` condition to check at all and are marked
  ready unconditionally instead: the plain `v1/Secret` connection mirror,
  and `ProviderConfig` (its own `status` is just a `Users` count).
- A `Grant`'s Kubernetes object name can't contain the underscores real
  Postgres role names do (`pg_monitor` fails RFC 1123 validation). The
  `memberOf` value passed to Postgres stays as-is; only the k8s name gets
  a sanitized slug.

`providerConfigRef: {kind: ProviderConfig, name: ...}` was confirmed
correct as originally guessed — no error on that field once the above
were fixed.

Still open:

- Whether a bare `Role` (no `Grant`) can actually connect to
  `databaseName` under Postgres's default `PUBLIC CONNECT`, or whether an
  explicit grant is needed in practice — not yet reached in live testing,
  blocked on the above until now.
- The GCP `WatchOperation`'s behavior against multiple `DatabaseInstance`s
  appearing concurrently (cluster-wide, unfiltered) — validated with
  `kustomize build` only.

## Alternatives considered

**Reuse today's cluster-scoped `ProviderConfig`/`Role` instead of the
namespaced API family.** Rejected: a namespaced XR composing a
cluster-scoped resource never receives an owner reference
([crossplane/crossplane#6361](https://github.com/crossplane/crossplane/issues/6361)) —
deleting the XR would never garbage-collect them.

**Fold the admin-credential bootstrap into `DatabaseCredentials` itself.**
Rejected: it conflates two different layers — provisioning an instance's
admin login (ADR-0009 §4's territory, driver-specific, done once at
instance-creation time) with issuing an application credential against an
already-admin-accessible instance. Keeping the GCP bootstrap a separate,
generic, cluster-wide watcher matches how RDS/FlexibleServer already keep
their own equivalent (the provider's own auto-generate field) outside the
credential-issuance layer entirely.

**A cluster-scoped XRD instead of namespaced.** Would avoid the
owner-reference gap without needing provider-sql's namespaced API. Rejected:
a cluster-scoped XR is created outside any application namespace, which
reintroduces the "which namespace does this belong to" ambiguity a
chart-facing resource shouldn't have.

**Revisiting ADR-0013's claim-CRD rejection wholesale.** Not done. That
rejection is about the *instance* layer having no cross-cloud abstraction
worth building. This ADR only wraps the credential layer for a dedicated
instance — a case ADR-0013 didn't evaluate, not a reversal of what it did
evaluate.

## References

- [ADR-0009](0009-crossplane-cloud-databases.md) §4 — the chart-creates-the-instance-directly posture this ADR leaves unchanged.
- [ADR-0013](0013-declarative-app-role-provider-sql.md) — the Role/Database/Grant/ProviderConfig/instance-connection mechanism this ADR replaces.
- [ADR-0014](0014-database-domain-namespace-consolidation.md) §2 — the domain-specific-placement convention Decision §6 deliberately departs from.
- `crossplane-contrib/provider-sql` `apis/namespaced/postgresql/v1alpha1` — confirmed directly from the installed `v0.14.0` package's own CRDs (`roles.postgresql.sql.m.crossplane.io`, `providerconfigs.postgresql.sql.m.crossplane.io`, `clusterproviderconfigs.postgresql.sql.m.crossplane.io`).
- [crossplane/crossplane#6361](https://github.com/crossplane/crossplane/issues/6361) — namespaced XRs composing cluster-scoped resources get no owner reference.
- [crossplane/crossplane#7572](https://github.com/crossplane/crossplane/pull/7572) — required-resource watching, Crossplane v2.4+, the mechanism this ADR's Composition relies on to react to the instance's own readiness without a separate `WatchOperation`.
