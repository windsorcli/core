---
title: "ADR-0016: Postgres app credentials — a shared ClusterProviderConfig and a narrow AppRole"
description: One ClusterProviderConfig per database instance, owned by that instance's own WatchOperation, plus an AppRole XRD covering only the application-credential case. Replaces this ADR's original per-XR ProviderConfig design, which live testing found deadlocks on teardown, and supersedes ADR-0013's app-role/monitor-role/instance-connection mechanism.
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
package's CRD — `v0.14.0` originally, `v0.16.1` since §4). Its
`credentials.connectionSecretRef` requires both `name` and `namespace`, so a
cluster-scoped config still reads a Secret in `system-database`.

This is the mechanism provider-sql actually provides for one config serving
many namespaces. The namespaced alternative cannot: `Role`'s
`providerConfigRef` has no `namespace` field at all (confirmed from the live
CRD), so a namespaced `Role` can only ever reference a `ProviderConfig` beside
it. A cluster-scoped config has no namespace to cross.

The config takes the instance's own name. There is exactly one per instance,
so nothing shares a name with anything, and the collision in Context becomes
structurally impossible rather than merely unlikely. A cluster-scoped config's
usage count spanning every namespace is then correct behaviour, not a bug.

### 2. The instance's own `WatchOperation` owns it, not any XR

A `WatchOperation` on each cloud driver's own component (`crossplane/aws-rds`,
`crossplane/azure-postgres`, `crossplane/gcp-cloudsql` — not a separate
component, since one is never installed without the other) watches its
instance kind and ensures two things exist for each one: the
`<instance>-connection` Secret in `system-database` (the admin credential
merged with the live endpoint), and the `ClusterProviderConfig` reading it,
annotated with the instance's own kind/apiVersion — which §5's
`postgres-monitor` needs and `ClusterProviderConfig` has no field of its own
to carry. Both carry an `ownerReference` to the instance,
`blockOwnerDeletion: false`: the instance can delete freely, and Kubernetes
garbage-collects these once it's actually gone.

Ownership is what the first design could not express. A namespaced XR
composing a cluster-scoped resource receives no owner reference at all
([crossplane/crossplane#6361](https://github.com/crossplane/crossplane/issues/6361)),
which is why the original went namespaced and per-XR. Here the owner is the
instance itself, cluster-scoped owning cluster-scoped, with none of that
problem.

The three drivers' scripts are near-identical, differing only in the watched
kind, the endpoint field, and how the admin username resolves — a `PostgresProviderConfig`
XR wrapping a shared Composition briefly existed here to collapse them into
one. It was reverted: consolidating three ~100-line scripts doesn't justify
a new CRD, a new Composition, and a second ownership hop, especially stacked
on top of two other new-XR mistakes already made and reverted earlier this
same session (§3). Some duplication across three files is the cheaper cost.

### 3. No `ClusterUsage`: ownership and orphan policies already cover teardown

An earlier revision of this ADR added a `ClusterUsage` (`of` the instance, `by`
the `ClusterProviderConfig`, `replayDeletion: true`) to block the instance's
deletion while its config existed, reaching for the same guarantee #2918 and
#2919 were after. A live full-context `windsor destroy` against `gcp-test`
showed it recreates the deadlock it was meant to prevent: the webhook denies
the instance's delete outright, without ever setting a `deletionTimestamp` on
it, so the owning `WatchOperation` gets no signal that deletion was attempted
and keeps re-creating the `ClusterProviderConfig`/`ClusterUsage` pair on every
reconcile. Flux tears down the `WatchOperation`'s own Kustomization only after
the instance's, so nothing ever stops the loop without manual intervention.

`Role` and `Grant` exclude `Delete` from `managementPolicies` (§4, §5), so
their own removal from Kubernetes issues no `DROP ROLE`/`REVOKE`. It does
still call `Observe` first — that policy is not excluded, and provider-sql's
reconciler needs it to succeed before it can conclude an object is safe to
orphan. Left to pure ownership GC, `postgres-monitor`'s `Role`/`Grant` —
owned by `ClusterProviderConfig`, which itself only disappears once the
instance is completely gone — reliably lost that race: `Observe` failed
against a database that no longer existed, and the finalizer never cleared.
Live, this needed one manual `kubectl patch ... finalizers: []` per full
teardown. §5 fixes this properly now, rather than leaving it open.

**A first attempted fix here was reverted.** A cluster-scoped
`InstanceConnection` XR, composed rather than built by a `WatchOperation`, on
the theory that a Composition can prune what it creates (Operations cannot —
see References) and so could react to the instance's `deletionTimestamp` by
proactively dropping `ClusterProviderConfig`/`ClusterUsage` while the
database was still reachable. Live, it reproduced the original deadlock: the
`nousages` admission webhook denies a blocked delete synchronously, before
Kubernetes persists anything, so `deletionTimestamp` never appears on an
object whose deletion `ClusterUsage` is blocking — no matter what's watching
for it. That's not an Operations-versus-Compositions gap; a blocked delete
leaves no observable trace for any passive watcher. Protection against
deleting a live, in-use instance belongs on the instance CR itself —
`deletionPolicy`/`deletionProtection`, the same fields RDS, Cloud SQL, and
Flexible Server already expose — not on a second Kubernetes object whose own
removal has no reliable trigger.

A second, unrelated XR briefly reused the name `InstanceConnection` for §2's
own `ClusterProviderConfig`/Secret — pure DRY, not deletion ordering, and it
never repeated this section's mistake (no `deletionTimestamp` check). It was
reverted anyway, for cost rather than a live bug; see §2.

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
namespace; two `Grant`s give it `ALL` on `databaseName` and `ALL` on the
`public` schema, matching what CloudNativePG's `bootstrap.initdb.owner`
already gives its app user. The second grant exists because Postgres 15+
revoked schema-level `CREATE` on `public` from `PUBLIC`
([core#2920](https://github.com/windsorcli/core/issues/2920)), and a
database-level grant doesn't cover it — a genuinely separate privilege
scope, only expressible with provider-sql `v0.16.1`'s `schema` field
(`v0.14.0` had none). `providerConfigRef` is filled in from `instanceName`,
so `ClusterProviderConfig` never appears in a consumer's manifest.

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

### 5. Monitoring is driver-agnostic, and composed, not built by a WatchOperation

`postgres-monitor`'s own `WatchOperation` watches `ClusterProviderConfig`
rather than the three cloud instance kinds — once one exists, every driver
difference is already resolved — but it now does only one thing: ensure a
`PostgresMonitor` XR exists, named after the server. `ClusterProviderConfig`
doesn't itself know what kind of server it belongs to, so §2's drivers
annotate it (`database.windsorcli.dev/server-{api-version,kind}`) when they
build it, and this `WatchOperation` copies those onto the XR's own spec.

The XR's Composition does the actual work, and unlike the `WatchOperation`
that used to build these directly, it can prune what it creates. It requires
the instance itself (using the annotated kind/apiVersion) and checks its
`deletionTimestamp`, the same pattern §3 rejected for `ClusterProviderConfig`
itself but which holds here: without `ClusterUsage`, the instance's deletion
is never blocked, so `deletionTimestamp` reliably appears and — confirmed
live — stays for minutes before the database actually disappears. Composing
none of `monitor-role`/`monitor-grant`/the exporter once it's set prunes
them while `Observe` can still succeed, closing the gap §3 left open: the
monitor's `Role`/`Grant` no longer race the database's own teardown.

The exporter Deployment/Service/PodMonitor was originally a second
`WatchOperation`, watching every `Role` cluster-wide for a label the monitor
one set, purely to learn the connection Secret's name — which it already
knows, since it derives that name itself when building the `Role`. There was
nothing the second hop learned that the first didn't already compute, so
it's one `compose()`: build the `Role`/`Grant`, and once the `Role` reports
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

Three full `windsor apply`/`windsor destroy` cycles against `gcp-test`, with
the demo app's `AppRole` and the monitor's credentials both present,
confirmed:

- `AppRole`'s `Role` resolving a `ClusterProviderConfig` reference and
  connecting: the demo app's credentials worked end to end, across all
  three cycles.
- Ordering between the `WatchOperation` creating the `ClusterProviderConfig`
  and `AppRole`'s `Role` referencing it before that watcher had run once:
  no issue observed.
- `demo-db`'s deletion no longer collides across namespaces the way #2917
  did, in any cycle.
- The `WatchOperation`-built `ClusterUsage` deadlocking a full teardown,
  exactly as §3 describes — reproduced live in the first cycle.
- §3's current design (no `ClusterUsage`) letting `demo-resources`,
  `database-resources`, and `provisioning-resources` all tear down with zero
  manual intervention, in both the second and third cycles.
- `postgres-monitor`'s own `Role`/`Grant` outliving the database they
  connect through, stuck on a failed `Observe` with no live controller path
  to clear it, needing one manual finalizer clear — reproduced live in both
  the second and third cycles. §5's `PostgresMonitor` Composition is meant
  to close this; see Not yet verified below.
- The `InstanceConnection` Composition attempt deadlocking the same way
  `ClusterUsage` originally did, for the reason §3 now records — reproduced
  live in the third cycle, then reverted.
- `GRANT ALL PRIVILEGES ON DATABASE` not covering Postgres 15+'s revoked
  `public` schema `CREATE` privilege — reproduced live in a fourth cycle
  ([core#2920](https://github.com/windsorcli/core/issues/2920)), fixed by a
  second, schema-scoped `Grant` (§4) on provider-sql `v0.16.1`. Live-verified
  against the demo's own PG16 instance: connected as `demo-app` and ran
  `CREATE TABLE`/`INSERT`/`SELECT`/`DROP TABLE`, all successful.

**Not yet verified**: §5's `PostgresMonitor`. It rests on a signal confirmed
live in the third cycle above — the instance's `deletionTimestamp` reliably
appearing and holding for minutes once nothing blocks its deletion — but
the Composition itself, and the annotations §2's drivers now write onto
`ClusterProviderConfig` for it to read, have not.

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
  implementation, which is why the `InstanceConnection` attempt in §3 could
  not have worked even without the `deletionTimestamp` problem it hit first.
