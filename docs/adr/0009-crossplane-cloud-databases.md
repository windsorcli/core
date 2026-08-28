---
title: "ADR-0009: Crossplane — application-requested cloud databases"
description: Adds database.postgres.driver: rds, installing Crossplane and provider-aws-rds so a Helm chart installed on top of core can request a cloud-managed Postgres database without the customer authoring their own blueprint. Scopes core#2515 down to the grounded case; no cross-cloud abstraction, no general-purpose Crossplane surface.
---

# ADR-0009: Crossplane — application-requested cloud databases

## Status

Proposed. Formalizes [core#2515](https://github.com/windsorcli/core/issues/2515), scoped to a single concrete need.

## Context

Core's provisioning model is Terraform: infrastructure is decided by the
platform operator at blueprint-compose time (`schema.yaml`/facets) and
applied by `windsor apply`, before any workload is installed. A customer
needs something this model can't produce — their application's Helm chart,
installed *after* `windsor apply` on top of an already-running core
cluster, requires a real cloud-managed database as an application
dependency. They cannot be required to author their own Windsor blueprint
just to get a database; the chart has to be installable on stock core.

Nothing reacts to a later `helm install`. Terraform's apply-time model has
no hook for a workload deciding, at its own install time, that it needs a
cloud resource.

Crossplane extends the Kubernetes API with CRDs a controller reconciles
against a cloud provider — the same operator-plus-CRD pattern core already
uses for CloudNativePG and External Secrets Operator, except the CRD here
represents a cloud resource instead of an in-cluster one. core#2515 asks
for Crossplane broadly — any `Provider`/`Composition`/`CompositeResourceDefinition`
as a general blueprint capability. This ADR scopes that down to what's
actually grounded: one application-level dependency, a cloud-managed
Postgres database, installed the same way core already installs CNPG.

`kustomize/database` today has only an `install/` tier for CloudNativePG —
core installs the operator; nothing in the repo creates the `Cluster` CR.
That's left entirely to whatever consumes it. The customer's Crossplane
need is the same posture: install the controller, let the chart create the
resource.

## Decision

### 1. `database.postgres.driver: rds` — a new enum value, not a new capability

```yaml
database:
  postgres:
    enabled: true
    driver: rds   # cloudnativepg | rds
```

Reuses the existing `database.postgres` capability rather than introducing
a top-level `crossplane` key. `enabled` gates the capability; `driver`
selects which controller fulfills the chart's database CR — exactly the
role it already plays for `cloudnativepg`.

### 2. `kustomize/provisioning/` — its own domain, named for the capability

Every existing kustomize domain is a capability noun with the vendor tool
nested under `install/` (`pki/install/cert-manager`,
`policy/install/kyverno`, `csi/install/{longhorn,openebs,...}`) — never
the vendor name as the domain itself, even when there's only one tool
today (`policy/install/kyverno`, not `kyverno/install/kyverno`). Crossplane
follows the same shape: `provisioning/install/crossplane` for the Helm
release. The namespace is `system-provisioning`, matching every other
domain's `system-<domain>` convention (`system-pki`, not
`system-cert-manager`). Crossplane is a general-purpose engine, not a
database concept — nesting its install under `kustomize/database/` would
misname what it is. `database.postgres.driver == 'rds'` is still what
turns it on: the `provisioning` `flux:` system entry lives in
`addon-database.yaml` and targets `kustomize/provisioning/`, the same
cross-domain-entry-in-a-driving-facet shape that facet's `observability`
entry already uses to target `kustomize/observability/`.

Crossplane's own core CRDs (`Provider`, `DeploymentRuntimeConfig`,
`Composition`, ...) are vendored under `kustomize/crds/crossplane-2.4.0`
— ~20 files from `crossplane/crossplane`'s `cluster/crds/`, the same
`urls:` mode `sources.yaml` already uses for Keycloak's 4 files. This
isn't the usual Helm-never-upgrades-CRDs justification (Crossplane's own
chart applies these itself via an init container at every start,
regardless of what's vendored, so the vendored copy is never the sole
authority the way cert-manager's is) — it exists purely so `install:` can
create `Provider`/`DeploymentRuntimeConfig` CRs without racing that init
container on first apply. With that race gone, `install:` carries the
HelmRelease and, in `install/crossplane/aws-rds`, the `Provider` CR that
requests `provider-aws-rds` plus the `DeploymentRuntimeConfig` it
references — ordinary CRs of already-registered kinds, no different from
any other resource an already-installed operator's chart happens to
create.

`provider-aws-rds`'s *own* CRDs are a second, genuinely separate gap:
they don't exist until Crossplane's package manager finishes pulling the
package the `Provider` CR requested, and that package isn't vendored (no
static release asset to pin the way Crossplane's own CRDs are — the
`Provider` CR's `spec.package` reference is the update surface instead).
`install:` carries `healthCheckExprs` on that `Provider` reporting
Healthy/Installed, and Crossplane only sets Installed=True once its CRDs
are registered — so `resources/crossplane/aws-rds` (the `ProviderConfig`,
plus a Kyverno `ClusterPolicy` with no such dependency of its own) is safe
the moment `install:` reports Ready, no explicit `dependsOn` needed beyond
the system's own implicit install-before-resources edge.
`install/crossplane/aws-rds` and `resources/crossplane/aws-rds` share the
same leaf name on purpose, the way `csi/install/longhorn` and
`csi/resources/longhorn` already do — same provider, split by lifecycle
stage, not two different things.

Core creates the `ProviderConfig`, named `default` — the field's own
default, so the chart's `Instance` CR needs no `providerConfigRef` at all,
closing the CNPG analogy exactly: the chart supplies only the database
definition. The customer's chart cannot safely create the `ProviderConfig`
itself, since it binds to a privileged IAM role.

### 3. IAM lives in `cluster/aws-eks/modules/crossplane-iam`

Every existing "a pod in this cluster needs an AWS IAM role via Pod
Identity" case — cert-manager, aws-lb-controller, cluster-autoscaler,
Karpenter's substrate, vpc-cni, ebs-csi, efs-csi — is wired directly in
[main.tf](../../terraform/cluster/aws-eks/main.tf), one flat hardcoded
block each, gated behind its own boolean var. Crossplane's IAM doesn't
follow that shape: it's a nested submodule,
[modules/crossplane-iam](../../terraform/cluster/aws-eks/modules/crossplane-iam),
`for_each` over a `crossplane_resources` set (currently `["rds"]` when
`database.postgres.driver == 'rds'`), matching the nesting pattern
[modules/machine](../../terraform/cluster/talos/modules/machine) already
uses under `cluster/talos/`. The module carries an internal catalog
mapping each supported resource type to its IAM policy, ServiceAccount,
and namespace — a second Crossplane-managed AWS resource type (S3, say)
means one new catalog entry, not a copy-pasted block in `main.tf`. Still
scoped under `cluster/aws-eks/` (§ Alternatives), not a new top-level
Terraform layer: a Pod Identity association is inherently
EKS-cluster-scoped, and none of the 9 existing layers (`backend`,
`network`, `cluster`, `cni`, `compute`, `dns`, `gitops`, `pki`,
`workstation`) are addon-scoped the way a `database` layer would be.

For `rds`, the module creates `aws_iam_role`, `aws_iam_policy`, and
`aws_iam_role_policy_attachment`, plus an `aws_eks_pod_identity_association`
— `cluster/aws-eks/main.tf` itself keeps only the `aws_db_subnet_group`
Crossplane-managed `Instance` resources reference by name (not an IAM
concern, out of the submodule's scope), spanning `isolated_subnet_ids`
(zero-egress, no NAT route), not `private_subnet_ids` (NAT-routed, what
EKS nodes use) — an RDS instance has no need for outbound internet access.
The policy is scoped to RDS instance lifecycle actions (`CreateDBInstance`,
`ModifyDBInstance`, `DeleteDBInstance`, tagging, snapshotting) within that
subnet group and the cluster's existing VPC — no VPC, subnet, or
security-group creation rights, out of Crossplane's reach. The trust
policy also carries an
`aws:SourceAccount`/`aws:SourceArn` condition scoping it to this
cluster's own Pod Identity Agent — a hardening step the other 7 Pod
Identity roles in `main.tf` don't have yet
([core#2584](https://github.com/windsorcli/core/issues/2584)).

An RDS ARN can't name an instance that doesn't exist yet, so the `Resource`
element alone is account/region-wide; a tag condition does the actual
scoping. `CreateDBInstance` requires `aws:RequestTag/windsorcli.dev/cluster`
to equal this cluster's name; `ModifyDBInstance`/`DeleteDBInstance`/tagging/
snapshotting require the same key as `aws:ResourceTag` on the instance
already. This role can create RDS instances and can only touch ones it
created — not an arbitrary instance elsewhere in the same AWS account.

The chart's `Instance` CR never has to set that tag itself. The
`resources/crossplane/aws-rds` kustomize component (§2) bundles a Kyverno
`ClusterPolicy` — `crossplane-rds-tag` — that force-sets
`windsorcli.dev/cluster` on every `Instance` admission via
`patchStrategicMerge`, overwriting whatever value, if any, the chart
submitted. `cluster_name` reaches the policy the same way `aws-lb-controller`
already gets `clusterName`: a Flux `substitutions:` entry sourced from
`terraform_output('cluster', 'cluster_name')`. `failurePolicy: Ignore` — if
the webhook is unreachable the create still goes through, and IAM's own
condition is the backstop that rejects a wrongly- or untagged instance
either way, so there's no window where a missing mutation becomes a
security hole.

The Pod Identity association needs a fixed `(namespace, service_account)`
pair, but Crossplane's package manager normally auto-generates the
provider pod's ServiceAccount name. A `DeploymentRuntimeConfig`
(`pkg.crossplane.io/v1beta1`) pins `serviceAccountTemplate.metadata.name:
provider-aws-rds`, referenced by the `Provider` CR's `runtimeConfigRef`,
so Terraform's association has a known name to target.

### 4. The chart creates Crossplane's native resource directly, no core abstraction

No core-authored claim CRD or XRD. The chart creates `provider-aws-rds`'s
own managed resource (`rds.aws.upbound.io/v1beta3 Instance`) directly — the
same posture as CNPG's `Cluster`. `driver: rds` names an AWS-specific shape
on purpose; there's no cross-cloud abstraction to preserve, matching
`cloudnativepg`, which doesn't abstract over a second engine either.

### 5. Azure is a known fast-follow, not designed here

`driver: rds` is AWS-only. A second value (Azure Database for PostgreSQL
via `provider-azure`) is a tracked gap — it needs its own IAM story (Azure
Workload Identity in place of Pod Identity) and isn't decided by this ADR.

## Consequences

- `Provider.spec.package` is digest-pinned
  (`provider-aws-rds:v2.7.1@sha256:...`), not just tagged — confirmed live
  that `ProviderRevision.spec.image` propagates this reference verbatim
  into the provider's runtime Deployment, so the digest satisfies
  `require-image-digest` with no policy exemption needed. Found live: the
  `Provider` resource first reported `Installed=True, Healthy=False`,
  blocked by a Kyverno admission denial on the provider's own runtime
  Deployment for lacking a digest. `provider-family-aws` (an automatic
  dependency of `provider-aws-rds`) hit the same denial and isn't
  reachable through a `Provider` CR of ours to pin directly — resolved by
  declaring it explicitly, also digest-pinned, with
  `skipDependencyResolution: true` on `provider-aws-rds` so Crossplane
  doesn't auto-resolve its own unpinned copy.
- `crossplane_rds`'s DB subnet group is the first consumer anywhere in
  this repo of `network/aws-vpc`'s `isolated_subnet_ids` output — the
  zero-egress subnet tier existed, unused, before this ADR.
- `system-provisioning` stays at PSA `baseline`, matching `system-database`
  — `restricted` (which `system-pki-trust` proves this repo does adopt
  per-namespace when the workload supports it) was tried and reverted.
  Crossplane's own chart carries the extra `securityContext` fields
  (`capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`)
  `restricted` needs beyond its defaults — verified with `kustomize
  build`, kept even at `baseline` since it doesn't hurt. The provider pod
  (`provider-aws-rds`) doesn't have the equivalent: its
  `DeploymentRuntimeConfig.spec.deploymentTemplate.spec` reuses
  `apps/v1 DeploymentSpec` verbatim, which requires `selector`, and
  Crossplane assigns that provider pod's real labels dynamically
  per-revision — a hand-written `selector` isn't safely determinable
  without deeper visibility into Crossplane's own labeling. Caught by a
  live cluster's dry-run validation, not `kustomize build`. `restricted`
  for this namespace is a real follow-up, not decided here.
- The customer's chart is coupled to `provider-aws-rds`'s own CR shape.
  Its API stability becomes something core's `Provider` package pin
  governs, the same exposure CNPG's `Cluster` CR already carries.
- `kustomize/provisioning/install/crossplane` installs the engine once,
  independent of which capability turned it on. A second Crossplane-backed
  resource type (e.g. `object_store.driver: crossplane` for S3) reuses that
  same install tier and adds its own `install/crossplane/<provider>` +
  `resources/crossplane/<provider>` pair alongside `aws-rds` — the domain
  is already structured for that, it just isn't built yet.
- Crossplane's IAM is a submodule, `cluster/aws-eks/modules/crossplane-iam`
  — `for_each` over a `crossplane_resources` set, with an internal
  per-resource-type catalog (policy document, ServiceAccount, namespace).
  Adding a second Crossplane-managed AWS resource type (e.g. S3) means one
  new catalog entry and one new allowed value in `crossplane_resources`,
  not a copy-pasted IAM block — unlike every *other* addon's Pod Identity
  role in `cluster/aws-eks/main.tf` (cert-manager, aws-lb-controller,
  cluster-autoscaler, Karpenter), which stay flat, one block each, since
  none of those are a family of similar resources expected to grow the way
  Crossplane's is. `crossplane-iam`'s trust policy also carries an
  `aws:SourceAccount`/`aws:SourceArn` condition scoping it to this
  cluster's Pod Identity Agent specifically — the other Pod Identity roles
  in this file don't have that yet ([core#2584](https://github.com/windsorcli/core/issues/2584)
  tracks bringing them in line).
- Enabling `driver: rds` with no chart installed does nothing observable,
  same as `external_secrets` alone: the `ProviderConfig` exists, nothing
  references it yet.
- The `crossplane-rds-tag` Kyverno policy lives inside
  `kustomize/provisioning/resources/crossplane/aws-rds/`, not `kustomize/policy/` —
  matching `kustomize/pki/resources/private-issuer/ca` bundling its own
  `inject-private-ca-policy.yaml` `ClusterPolicy` next to its
  `ClusterIssuer`. A capability's own Kyverno policy ships with the
  capability, so it's automatically present whenever that capability is,
  not a separate gate to keep in sync.
- Vendoring Crossplane's own CRDs costs a second upstream source to track
  (`crossplane/crossplane` releases, alongside the `crossplane` Helm chart
  version) that Renovate needs to bump together — the vendored copy and
  the running chart's embedded schema can drift on a version mismatch,
  unlike cert-manager's vendored CRDs, which the chart never touches at
  all once `crds: Skip` is set.

## Alternatives considered

**Customer authors their own blueprint.** Ruled out by the requirement
itself — the chart has to install on stock core via `windsor apply` then
`helm install`, not a bespoke per-deployment blueprint.

**A new top-level `crossplane` capability instead of a `database.postgres`
driver value.** More honest to Crossplane being a generic engine, and
sidesteps the shared-install question in Consequences above. Rejected for
now: the concrete need is a database, `database.postgres` already has the
right `enabled`/`driver` surface, and the CNPG precedent (install-only,
consumer creates the native CR) transfers directly. Revisit if a second
resource type materializes.

**A core-authored claim CRD abstracting AWS and Azure behind one type.**
Buys chart-author portability across clouds. Costs real design and
maintenance work now, for a need that's AWS-only today and has no CNPG-side
precedent for cross-vendor abstraction either. Rejected for v1.

**Terraform, decided at blueprint-compose time.** The actual gap this ADR
closes — a chart installed after `windsor apply` has no way to trigger a
Terraform apply.

**Two `resources:` tiers, nothing in `install:` but the HelmRelease.**
The first working version of this design: `Provider`/`DeploymentRuntimeConfig`
and `ProviderConfig` both as `resources:` tiers, chained by `dependsOn` +
`healthCheckExprs`, with no CRD vendoring. Correct, but put a CR ahead of
its CRD-installing operator's own tier for no reason — `install:` existed
and had nothing to do besides the HelmRelease. Vendoring Crossplane's own
CRDs (§2) removed the actual race that motivated keeping `Provider` out of
`install:`, so it moved there instead, leaving `resources:` with exactly
the one CR (`ProviderConfig`) whose CRD genuinely isn't available yet.

**A new top-level Terraform layer for the Crossplane IAM substrate**
(e.g. `terraform/database/`). Rejected: no existing layer is addon-scoped
— the 9 layers (`backend`, `network`, `cluster`, `cni`, `compute`, `dns`,
`gitops`, `pki`, `workstation`) are horizontal infra concerns, and a Pod
Identity association is inherently an EKS-cluster-scoped object. A nested
submodule under `cluster/aws-eks/` (§3, `modules/crossplane-iam`) is the
accepted answer instead — matching `cluster/talos/modules/machine`'s own
shape, not inventing a new top-level layer.

**Every Pod Identity role in `cluster/aws-eks/main.tf` stays a flat,
individually-hardcoded block, including Crossplane's.** Matches the
existing style for cert-manager, aws-lb-controller, cluster-autoscaler,
and Karpenter's substrate exactly. Rejected once it was clear Crossplane's
IAM is a genuinely different shape from those: a family of near-identical
resource types expected to grow (RDS today, S3/SQS/etc. plausible next),
not a fixed, closed set core ships permanently. `crossplane-iam` earns its
abstraction from that growth expectation, not from `modules/machine`'s
usual bar of three proven instantiations.

## References

- [core#2515](https://github.com/windsorcli/core/issues/2515) — the issue
  this ADR scopes down.
- `contexts/_template/facets/addon-database.yaml`,
  `kustomize/database/install/cloudnativepg` — the install-only,
  consumer-creates-the-CR precedent this ADR follows.
- [main.tf](../../terraform/cluster/aws-eks/main.tf) (`aws_iam_role.ebs_csi`,
  `efs_csi`, `karpenter_controller`) — the EKS Pod Identity role pattern
  this ADR's IAM wiring follows, and the precedent for keeping addon IAM
  colocated with the cluster module rather than split into a new layer.
- [modules/machine](../../terraform/cluster/talos/modules/machine) — the
  nested-submodule precedent `modules/crossplane-iam` follows.
- [ADR-0004](0004-external-secrets-operator.md) — the other
  install-only-controller precedent in this sequence.
- `kustomize/crds/sources.yaml` — the `crossplane` vendor entry and the
  `urls:` mode precedent (`keycloak`) it follows.
- [core#2584](https://github.com/windsorcli/core/issues/2584) — bringing
  the other 7 Pod Identity roles in `cluster/aws-eks/main.tf` up to
  `crossplane-iam`'s trust-policy scoping.
- Crossplane: [crossplane.io](https://crossplane.io). provider-aws-rds
  (Upbound): [marketplace.upbound.io/providers/upbound/provider-aws-rds](https://marketplace.upbound.io/providers/upbound/provider-aws-rds).
