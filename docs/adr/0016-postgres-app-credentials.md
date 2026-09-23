---
title: "ADR-0016: Postgres app credentials — a shared ClusterProviderConfig and a narrow AppRole"
description: One ClusterProviderConfig per database instance, composed by a cluster-scoped InstanceConnection XR that a driver's WatchOperation ensures exists, plus an AppRole XRD covering only the application-credential case. Replaces this ADR's original per-XR ProviderConfig design, which live testing found deadlocks on teardown, and supersedes ADR-0013's app-role/monitor-role/instance-connection mechanism.
---

# ADR-0016: Postgres app credentials — a shared ClusterProviderConfig and a narrow AppRole

## Status

Proposed. Supersedes [ADR-0013](0013-declarative-app-role-provider-sql.md)'s
`app-role`, `monitor-role`, and `instance-connection` components.

Replaces this ADR's own first design — a `DatabaseCredentials` XR that
composed its own `ProviderConfig` — which shipped, then deadlocked on
teardown in a live `gcp-test` run. The Context section below records that
failure, because the shape of this decision follows directly from it.

Verified live against `gcp-test`; see Live verification.

## Context

The original design gave every `DatabaseCredentials` XR its own namespaced
`ProviderConfig`, connection Secret, `Role`, and `Grant`s, all owned by that
XR. The reasoning was ownership: two XRs targeting one instance each got
their own objects rather than fighting over a shared one.

That held, until every such `ProviderConfig` got the same name. The name was
derived from the instance (`provider-sql-<instance>`), so the demo app's
config in `demo-database` and the monitor's config in `system-database` were
two distinct objects sharing one name.

[core#2917](https://github.com/windsorcli/core/issues/2917) reported the
symptom: `demo-database` hanging in `Terminating`, its `ProviderConfig` stuck
on the `in-use.crossplane.io` finalizer, until the owning Kustomization's own
timeout force-removed it. Two attempted fixes missed:

- [core#2918](https://github.com/windsorcli/core/pull/2918) added a `Usage`
  to block the instance's deletion while its `ProviderConfig` existed. Live,
  the instance deleted anyway: `Usage`'s `of.resourceRef.namespace` defaults
  to the `Usage`'s own namespace when omitted
  (`internal/controller/protection/usage/reconciler.go`, read directly), so
  the guard was watching a namespaced path where nothing existed.
- [core#2919](https://github.com/windsorcli/core/pull/2919) set that
  namespace explicitly. The webhook then denied the delete, correctly — and
  named the real problem: `This resource is in-use by 2 usage(s), including
  the Usage "provider-sql-demo-db-usage" (in namespace "system-database") by
  resource ProviderConfig/provider-sql-demo-db`.

A full `windsor destroy kustomize` against `gcp-test` then reproduced the
original hang and showed the mechanism. `demo-database`'s own `Role`/`Grant`
were confirmed gone, yet its `ProviderConfig` reported `users: 2`. Listing
every `ProviderConfigUsage` in the cluster — the kind is itself namespaced —
returned exactly two, both in `system-database`, both naming
`CONFIG-NAME: provider-sql-demo-db`. **provider-sql's usage accounting matched
those by name alone, across namespaces.** `demo-database`'s config was held
open by objects belonging to an unrelated config that happened to share its
name.

Under a full-context destroy that is circular, not merely slow.
`demo-resources` cannot finish until its `ProviderConfig` clears; that config
will not clear until `system-database`'s monitor credentials are gone; those
belong to `provisioning-resources`, which Flux destroys only after
`demo-resources` succeeds. The run ended as the issue described: `windsor
timed out after 1h0m0s waiting for kustomization system-gitops/demo-resources
to delete. Namespace/demo-database from its inventory is still live`.

Duplicating a semantically shared object per consumer is what created the
collision. This ADR stops duplicating it.

## Decision

### 1. One `ClusterProviderConfig` per instance, named after the instance

`crossplane-contrib/provider-sql` ships `ClusterProviderConfig` alongside the
namespaced `ProviderConfig` (`scope: Cluster`, confirmed against the installed
`v0.14.0` package's CRD). Its `credentials.connectionSecretRef` requires both
`name` and `namespace`, so a cluster-scoped config still reads a Secret in
`system-database`.

This is the mechanism provider-sql actually provides for one config serving
many namespaces. The namespaced alternative cannot: `Role`'s
`providerConfigRef` has no `namespace` field at all (confirmed from the live
CRD), so a namespaced `Role` can only ever reference a `ProviderConfig` beside
it. A cluster-scoped config has no namespace to cross.

The config takes the instance's own name. There is exactly one per instance,
so nothing shares a name with anything, and the collision in Context becomes
structurally impossible rather than merely unlikely. A cluster-scoped config's
usage count spanning every namespace is then correct behaviour, not a bug.

### 2. The instance's own `WatchOperation` ensures an `InstanceConnection` XR, not the plumbing itself

A `WatchOperation` on each cloud driver's own component (`crossplane/aws-rds`,
`crossplane/azure-postgres`, `crossplane/gcp-cloudsql` — not a separate
component, since one is never installed without the other) watches its
instance kind and ensures exactly one thing: a cluster-scoped
`InstanceConnection` XR named after the instance, carrying the four fields
that vary by driver (`instanceApiVersion`, `instanceKind`, `endpointField`,
`adminUsernameField`) and an `ownerReference` to the instance,
`blockOwnerDeletion: false`, as a backstop.

Ownership is what the first design could not express. A namespaced XR
composing a cluster-scoped resource receives no owner reference at all
([crossplane/crossplane#6361](https://github.com/crossplane/crossplane/issues/6361)),
which is why the original went namespaced and per-XR. Here the owner is the
instance itself, cluster-scoped owning cluster-scoped, with none of that
problem.

### 3. `InstanceConnection`'s Composition builds the plumbing, and prunes it on deletion

A `WatchOperation` cannot delete anything it creates — Crossplane's own docs
list this as a current limitation of Operations. An earlier revision of this
ADR reached for a `ClusterUsage` (`of` the instance, `by` the
`ClusterProviderConfig`, `replayDeletion: true`) built directly by the
`WatchOperation`, the same guarantee #2918 and #2919 were after. Live, this
recreated the deadlock it was meant to prevent: the webhook denies the
instance's deletion outright, so the `WatchOperation` keeps re-asserting the
same `ClusterUsage` it can never remove, forever.

A follow-up revision dropped `ClusterUsage` outright, reasoning that `Role`
and `Grant` exclude `Delete` from `managementPolicies` so their own removal
needs no live connection. That missed that `Observe` is not excluded, and
provider-sql's reconciler calls it before it can conclude an object is safe
to orphan. Once the instance is actually gone, `Observe` fails forever and
the finalizer never clears — reproduced live against `postgres-monitor`'s own
`Role`/`Grant` in a full `gcp-test` teardown.

Only a Composition can prune what it creates: composing a resource once and
omitting it on a later reconcile deletes it, which is exactly the capability
Operations lack. `InstanceConnection`'s one Composition (shared by every
driver, parameterized by the XR's own spec) requires the instance itself as
an extra resource and checks its `deletionTimestamp`:

- Not set: compose the `<instance>-connection` Secret (the admin credential
  merged with the live endpoint), the `ClusterProviderConfig` reading it, and
  the `ClusterUsage` blocking the instance's deletion while they exist.
- Set: compose none of the three. Crossplane prunes them, and deleting the
  `ClusterUsage` replays the instance's now-safe deletion.

Pruning fires within a reconcile of the delete request, well before the
instance's own provider finishes tearing down the real cloud resource — so
`postgres-monitor`'s `Role`/`Grant`, garbage-collected once the
`ClusterProviderConfig` they're owned by disappears, still find a live
database to `Observe` against.

### 4. `AppRole` — deliberately narrow, the CloudNativePG app-user equivalent

A chart names an instance and a database. It gets a login role owning that
database, and a Secret:

```yaml
apiVersion: database.windsorcli.dev/v1alpha1
kind: AppRole
metadata:
  name: demo-app
  namespace: demo-database
spec:
  instanceName: demo-db
  databaseName: demo
```

Two fields, and nothing else configurable. The Postgres role name is the
object's own name; the Secret is `<name>-credentials` in the object's own
namespace; the grant is `ALL` on `databaseName`, which is what an application
running its own migrations needs and what CloudNativePG's `bootstrap.initdb.owner`
already gives its app user. `providerConfigRef` is filled in from
`instanceName`, so `ClusterProviderConfig` never appears in a consumer's
manifest.

The narrowness is the point. `superUser`, `createRole`, `createDb`,
`bypassRls`, `replication`, role membership, and privilege subsets are all
reachable on provider-sql's own `Role`/`Grant` and none are exposed here —
a one-line field making privilege escalation convenient is worse than making
someone author the real resource. `AppRole` names the case it covers rather
than the primitives it composes, which is why it is not `DatabaseUser`: a
generalized user type would invite exactly the knobs this one refuses.

The Composition composes only `Role` and `Grant`. Both genuinely belong 1:1 to
the request that asked for them, so XR ownership is correct for them in a way
it never was for `ProviderConfig`.

### 5. Monitoring becomes driver-agnostic, and one WatchOperation, not two

`postgres-monitor` watches `ClusterProviderConfig` rather than the three cloud
instance kinds: once one exists, every driver difference is already resolved.
It creates the `<instance>-monitor` `Role` and its `pg_monitor` `Grant` in
`system-database`, replacing `aws-rds-monitor`, `azure-postgres-monitor`, and
`gcp-cloudsql-monitor` — three near-identical scripts collapsing into one.

The exporter Deployment/Service/PodMonitor was originally a second
`WatchOperation`, watching every `Role` cluster-wide for a label the monitor
one set, purely to learn the connection Secret's name — which it already
knows, since it derives that name itself when building the `Role`. There was
nothing the second hop learned that the first didn't already compute, so it's
one `operate()` now: build the `Role`/`Grant`, and once the `Role` reports
`Ready`, build the exporter reading the Secret that `Role` writes. Both stay
gated on `telemetry.metrics.enabled`; the components in §2 do not, since a
chart's own credentials depend on them regardless of whether anything scrapes
metrics.

The same reasoning folded `gcp-admin-password` into `crossplane/gcp-cloudsql`'s
own `WatchOperation` rather than leaving it separate: both watched
`DatabaseInstance` unconditionally, both were gated on the same
`cloud_driver == 'cloudsql'` condition, and the connection watcher already
waited on the admin Secret the password watcher produced. Two components that
are always installed together, watching the same object, one waiting on the
other's output, is one component that does two sequential things.

### 6. Anything `AppRole` does not cover is authored directly

A role needing membership in another role, a privilege subset, or any `Role`
field `AppRole` withholds, authors provider-sql's `Role`/`Grant` itself,
referencing the instance's `ClusterProviderConfig` by name. This is the
posture [ADR-0013](0013-declarative-app-role-provider-sql.md) §2 already took
for `Grant` — "the chart creates Crossplane's native resource directly, no
core abstraction" — now the documented escape hatch for the whole surface.
Those consumers do see `ClusterProviderConfig`. That is the one place the
plumbing leaks, and it leaks only to consumers who have already stepped
outside the common case.

## What's unchanged

- Admin credential provisioning stays what each driver already does:
  RDS/Flexible Server generate it via their own `passwordSecretRef`
  field, Cloud SQL via `gcp-admin-password`'s `WatchOperation` and the
  `User` CR it composes.
- A chart still creates the native `Instance`/`FlexibleServer`/
  `DatabaseInstance` CR directly — [ADR-0009](0009-crossplane-cloud-databases.md)
  §4, untouched — and its own database-creation CR where the cloud needs one.
- The admin credential still lives only in `system-database`. Consumers still
  receive only their own scoped role's Secret.

## Live verification

Two full `windsor apply`/`windsor destroy` cycles against `gcp-test`, with
the demo app's `AppRole` and the monitor's credentials both present,
confirmed:

- `AppRole`'s `Role` resolving a `ClusterProviderConfig` reference and
  connecting: the demo app's credentials worked end to end, across both
  cycles.
- Ordering between the `WatchOperation` creating the `ClusterProviderConfig`
  and `AppRole`'s `Role` referencing it before that watcher had run once:
  no issue observed.
- `demo-db`'s deletion no longer collides across namespaces the way #2917
  did, in either cycle.
- The `WatchOperation`-built `ClusterUsage` from this ADR's first revision
  deadlocking a full teardown exactly as described in §3 — reproduced live,
  which is what drove that section's redesign.
- The no-`ClusterUsage` revision of §3 letting `postgres-monitor`'s own
  `Role`/`Grant` outlive the database they connect through, stuck on a
  failed `Observe` with no live controller path to clear it — also
  reproduced live, which is what drove the `InstanceConnection` Composition
  now in §3.
- `GRANT ALL PRIVILEGES ON DATABASE` still needs a real migration run against
  Postgres 15+'s revoked `public` schema `CREATE` privilege — not exercised
  by either cycle, and still open.

**Not yet verified**: the `InstanceConnection` Composition itself (current
§3) — both live cycles above ran against its two predecessors, not this
version. `kustomize build` and the Composition script's syntax are checked;
its actual prune-on-`deletionTimestamp` behavior is not.

## Alternatives considered

**Give each XR's `ProviderConfig` a unique name.** The minimal fix: a
uniquely-named `demo-database` config would not have counted
`system-database`'s resources, and the deadlock would not have occurred.
Rejected as the destination rather than as a stopgap — it leaves the admin
credential copied into every consumer's namespace, leaves N near-identical
configs per instance, and keeps the per-XR `Usage` machinery that produced
two failed fixes. #2919 remains open as exactly this stopgap while the
change here is verified.

**Encode the request as annotations on the instance CR, for a single CR
total.** Rejected: the instance kinds are cluster-scoped
(`rds.aws.upbound.io` has no namespaced kinds, per ADR-0009), so an
annotation cannot express several namespaces each wanting their own
credential off one shared instance, and setting it would need cluster-scoped
edit rights rather than namespaced create rights.

**Provision the app credential fully automatically, the way `monitor`
already is.** Tempting, since `postgres-monitor` needs no consumer object at
all. It cannot generalize: `monitor`'s Secret goes to `system-database`,
which core owns, while an app's Secret must land in the consumer's namespace,
and a cluster-scoped instance carries nothing that identifies which namespace
that is. The namespace is irreducible consumer-supplied input; something
namespaced has to exist.

**Inject `providerConfigRef` with a Kyverno mutating policy**, so consumers
author bare `Role`/`Grant` without naming a config. Workable — this repo
already mutates admission for the `windsorcli.dev/cluster` tag — but it hides
a required field outside Crossplane's own model, leaving a manifest that does
not mean what it says when read on its own.

**Name the `ClusterProviderConfig` `default`.** `providerConfigRef` defaults
to `{kind: ClusterProviderConfig, name: default}`, so consumers could omit
the field entirely — the genuinely native answer. Rejected because contexts
really do run more than one instance, and only one object cluster-wide can
be named `default`.

**No XR at all: consumers author `Role` and `Grant` directly.** Rejected on
two concrete regressions from CloudNativePG parity, not on taste.
`writeConnectionSecretToRef.name` is a required field with no default, so
every consumer must invent a Secret name; and the common case needs two
coordinated objects, where forgetting the `Grant` yields a role that connects
and can do nothing, with no error to point at.

**A generalized `DatabaseUser` XR.** The name invites the privilege knobs §4
deliberately withholds, and a type that grows `superuser` is a different
thing from the one this covers.

**A namespaced XR composing the instance itself**, restoring CloudNativePG's
actual property that instance and consumer share a namespace. The only design
that achieves true single-CR parity. Rejected for teardown: crossplane#6361
means such an XR gets no owner reference on the cluster-scoped instance, so
deleting it would leave the cloud database running and billing.

## References

- [core#2917](https://github.com/windsorcli/core/issues/2917),
  [core#2918](https://github.com/windsorcli/core/pull/2918),
  [core#2919](https://github.com/windsorcli/core/pull/2919) — the teardown
  hang and the two fixes that missed it.
- [ADR-0009](0009-crossplane-cloud-databases.md) §4 — the
  chart-creates-the-instance posture, and the cluster-scoped instance
  constraint this ADR's alternatives rest on.
- [ADR-0013](0013-declarative-app-role-provider-sql.md) — `instance-connection`
  first proposed one config per instance; §2 established the
  author-it-yourself posture §6 generalizes.
- [crossplane/crossplane#6361](https://github.com/crossplane/crossplane/issues/6361)
  — namespaced XRs composing cluster-scoped resources get no owner reference.
- `crossplane-contrib/provider-sql` `apis/namespaced/postgresql/v1alpha1` —
  `clusterproviderconfigs`, listed as installed by this ADR's first revision
  and unused until now.
- [Crossplane Operations docs](https://docs.crossplane.io/latest/operations/operation/)
  — "delete resources" listed as a current limitation of the alpha
  implementation, which is why §3 moved pruning to a Composition.
