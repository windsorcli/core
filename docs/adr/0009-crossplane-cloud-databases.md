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

### 3. Support infra splits three ways, by what actually varies together

Every existing "a pod in this cluster needs an AWS IAM role via Pod
Identity" case — cert-manager, aws-lb-controller, cluster-autoscaler,
Karpenter's substrate, vpc-cni, ebs-csi, efs-csi — is wired directly in
[main.tf](../../terraform/cluster/aws-eks/main.tf), one flat hardcoded
block each, gated behind its own boolean var. RDS support infra doesn't
belong there at all: none of it describes the EKS cluster, and unlike
those cases it's a capability a *customer's chart* opts into, not one of
core's own add-ons. It splits into three pieces, each living where its
own reason to change actually points:

**`network/aws-vpc`** gains `aws_db_subnet_group.main`, spanning the
isolated (zero-egress, no NAT route) subnets — created unconditionally,
the same way the isolated subnet tier itself already is, regardless of
whether `database.postgres.driver` is even `rds`. It's the most neutral
of the three: a pure networking construct, naturally shared across every
database in a context rather than created per-instance, with no engine or
encryption opinion of its own.

**`terraform/database/aws-rds`**, a new top-level layer, owns the KMS key
RDS storage encryption uses. Named for the capability, not the mechanism
— encryption is a property of the data, independent of whether Crossplane
or (someday) Terraform itself creates the actual RDS instance. A
Terraform-native database mode, decided at blueprint-compose time instead
of by a customer's chart, is a real future shape and a fundamentally
different mechanism from this ADR's — but it would *extend* this same
layer (add the instance resource, still keyed by the same encryption
story) rather than need a new one, so the name was never reserved against
a collision, it just never described an engine to begin with.

**`terraform/provisioning/crossplane-iam`**, also a new top-level layer,
owns the IAM role, policy, and Pod Identity association Crossplane's
`provider-aws-rds` pod needs. Unlike the KMS key, this genuinely *is*
engine-specific: Pod Identity exists only because a Crossplane provider
pod needs credentials to call AWS on the cluster's behalf, a need no
Terraform-native mode would share (`windsor apply`'s own credentials
would create that instance directly, no in-cluster pod involved). Named
`provisioning` to match `kustomize/provisioning/`'s own top-level name for
the identical reason — this is Crossplane's own wiring, not a database
concept. It keeps the `for_each`-over-a-`resources`-set catalog shape a
single, un-split module used to have: a second Crossplane-managed AWS
resource type (S3, say) means one new catalog entry here, a genuinely
repeated shape IAM policies share and KMS keys don't.

Both new layers are top-level, not nested under `cluster/aws-eks/` the
way an earlier version of this design put them — matching precedent this
ADR previously undersold. `pki/ca` and `dns/zone/route53` are both already
addon-scoped top-level Terraform layers, gated by their own `when:` the
same way `database`/`crossplane-iam` are gated on
`database.postgres.driver == 'rds'`; a Pod Identity association being
EKS-cluster-scoped was never actually a reason it had to live *inside*
the cluster module, only that it needs the cluster's outputs — the same
relationship `dns-zone`'s `zone_id` already has to `cluster`, just with
the dependency direction reversed (`crossplane-iam` depends on `cluster`
and `database`'s outputs, not the other way around).

`crossplane-iam`'s policy is scoped to RDS instance lifecycle actions
(`CreateDBInstance`, `ModifyDBInstance`, `DeleteDBInstance`, tagging,
snapshotting) within the shared subnet group and the cluster's existing
VPC — no VPC, subnet, or security-group creation rights, out of
Crossplane's reach. `CreateDBInstance` also needs an explicit `Allow` on
the `subgrp:*` ARN the instance references, not just the `db:*` ARN it
creates — AWS authorizes the action against every resource it touches,
not only the one being created. Found live: an `Instance` create failed
with an `AccessDenied` naming the DB subnet group ARN specifically, not
the instance ARN the policy already covered.

The policy also allows `iam:CreateServiceLinkedRole`, scoped to
`AWSServiceRoleForRDS` with a condition on `iam:AWSServiceName`, matching
[AWS's own documented policy for it](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAM.ServiceLinkedRoles.html)
— every AWS account needs this service-linked role to exist once before
any RDS instance can ever be created in it, and this role has no other
IAM permissions to self-bootstrap it otherwise. Found live: `demo-db`'s
first create attempt (once the subnet-group ARN fix above landed) failed
with `InvalidParameterValue: ... permission to create service linked
role` — `aws-test`'s first RDS instance in this account.

The policy also allows `kms:DescribeKey` and `kms:CreateGrant` (the
latter conditioned on `kms:GrantIsForAWSResource`) against whichever KMS
key ARN `database/aws-rds` resolves — even an AWS-managed key needs the
calling role's own IAM grant to use it, since its key policy delegates
back to identity-based policy rather than allowing every principal
outright. Found live: `demo-db`'s create attempt (once the
service-linked-role fix above landed) failed with
`KMSKeyNotAccessibleFault` naming the key `[null]` — leaving `kmsKeyId`
unset on the `Instance` CR and relying on `storageEncrypted: true` to
imply the default key doesn't satisfy this IAM policy's scoped grant, even
though AWS resolves the same default key either way.

`database/aws-rds` resolves that ARN with the same precedence
`secrets_encryption_kms_key_id`/`ebs_volume_kms_key_id` already use in
`cluster/aws-eks`: an explicit `kms_key_arn`
(`database.postgres.encryption.kms_key_arn` in schema — BYOK, for a
key the customer already manages) wins if set; otherwise a dedicated
`aws_kms_key.rds` is created, one per context, shared across every
database rather than one per resource or per instance — AWS's own
guidance is to key per use-case, not key per resource, and
rotation/revocation/audit trail are exactly what the AWS-managed default
key can't give a customer. `ephemeral == true` (CI, throwaway test
contexts) skips the dedicated key in favor of the AWS-managed default
(`alias/aws/rds`, looked up via `data.aws_kms_key.rds_default`), the same
posture `manage_log_group` already uses for the control-plane log group —
a short-lived context's data has no lifetime for a CMK's rotation/audit
story to matter for.

`manageMasterUserPassword: true` needs a second, unrelated set of
permissions: `secretsmanager:CreateSecret` and `secretsmanager:TagResource`
(scoped to `secret:rds!*`, the fixed prefix RDS-managed secrets always
use), plus `kms:DescribeKey` against the account's `aws/secretsmanager`
key — required per
[AWS's own documented permissions for this integration](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html#rds-secrets-manager-permissions)
regardless of which key ends up encrypting the secret, since the
`Instance` CR doesn't set `masterUserSecretKmsKeyId` and RDS defaults to
that key. Found live: once the storage-encryption KMS grant above was in
place, `demo-db` hit the exact same `KMSKeyNotAccessibleFault` error
shape again — a second, different KMS key this time, for a completely
separate purpose RDS's error message doesn't distinguish from the first.

**Naming convention is the documented contract for a third-party chart,
not for the demo.** `dbSubnetGroupName` and `kmsKeyId` both have to be
values a *third-party* chart — installed separately from core's own
blueprint — can supply itself. That chart has no access to Flux's
`postBuild.substitute`; that mechanism only resolves inside Windsor's own
blueprint-compiled Kustomizations. So the documented contract is a
deterministic name, not a `terraform_output` pass-through: the subnet
group is always named `<context_id>-rds`, and the dedicated CMK (the
self-managed path only — AWS-managed keys can't take a custom alias, per
[AWS's own docs](https://docs.aws.amazon.com/kms/latest/developerguide/alias-authorization.html))
gets a matching `alias/<context_id>-rds` alias. The ephemeral path
references `alias/aws/rds` directly — already a fixed AWS name, not one
Windsor invents. BYOK isn't coverable by an alias at all: aliasing a key
the operator owns would need `kms:CreateAlias`/`kms:DeleteAlias`
permission on it, which core has no business assuming — the operator who
set `database.postgres.encryption.kms_key_arn` already knows that ARN and
hands it to their chart some other way.

The demo itself doesn't use this convention — it's Windsor's own tooling,
with real Flux substitution access a third-party chart lacks, so it reads
`terraform_output('network', 'db_subnet_group_name')` and
`terraform_output('database', 'kms_key_arn')` directly. That's strictly
better for the demo specifically: no risk of drifting from whatever
`network`/`database` actually name things if that logic ever changes, and
it covers BYOK correctly too, since the module's own precedence already
resolves to the right ARN regardless of path — the alias convention above
can't. The naming-convention paragraph above stays the reference for
what a real chart has to do; the demo simply isn't bound by the same
constraint that makes it necessary.

`crossplane-iam`'s trust policy also carries an
`aws:SourceAccount`/`aws:SourceArn` condition scoping it to this
cluster's own Pod Identity Agent — a hardening step the other 7 Pod
Identity roles in `cluster/aws-eks/main.tf` don't have yet
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

### 6. Network access is scoped to the cluster's own security group

`network/aws-vpc`'s default security group denies all traffic
(`ingress = []`), so an `Instance` with no explicit `vpcSecurityGroupIds`
is unreachable from any pod — found by inspection, not live, while
designing the credential path below: nothing had actually verified an
application could reach the database at all. `database/aws-rds` creates
a dedicated security group allowing Postgres (5432) from
`cluster/aws-eks`'s own auto-created cluster security group, not the
whole VPC CIDR. That security group is attached directly to every node's
primary ENI by EKS itself, so it scopes correctly regardless of CNI
driver (AWS VPC CNI or Cilium) without needing per-pod security groups
(an AWS VPC CNI-only feature — Cilium can't do it, so it isn't a
CNI-portable answer here). It's tighter than the VPC CIDR without adding
any new moving parts: no per-namespace or per-pod security-group
mechanism exists at the AWS networking layer at all — that boundary has
to be enforced by the database's own authentication instead (§7).

Maintenance and developer access follows the same shape this repo
already uses for everything else — no VPN or bastion host. A temporary
pod with a Postgres client, started inside the cluster
(`kubectl run ... --image=postgres:16-alpine -- sleep infinity`, then
`kubectl exec`), already sits inside the allowed security group and
needs no new AWS infrastructure. `kubectl port-forward` to that pod
extends the same access to a developer's local client without a private
network path from their machine to the VPC at all. A Client VPN or SSM
Session Manager port-forwarding setup is a reasonable upgrade if there's
ever a need for persistent private network access for other reasons —
it isn't justified for this alone.

### 7. Application credentials, not the admin secret

`manageMasterUserPassword: true` generates the RDS master user — full
superuser privileges, DDL and GRANT included — and AWS's API design means
even Terraform's own `aws_db_instance` resource can't read its plaintext;
only the calling principal's own IAM can, via
`secretsmanager:GetSecretValue`. Handing that credential straight to a
consuming application, even in a genuinely 1:1 microservice-to-database
pattern, throws away CNPG's own convention this ADR otherwise mirrors:
CNPG never gives an app its superuser secret, only a separate,
database-scoped one. A compromised app with the master credential can do
far more than exfiltrate its own data — alter the schema, drop tables,
grant itself new privileges that outlive the original compromise. 1:1
ownership narrows *whose* data is at risk, not *how much* an app's own
vulnerability can do once it has admin rights.

No existing mechanism in this repo bridges an AWS-generated runtime
secret into Kubernetes. External Secrets Operator is the standard tool
for exactly that, but isn't merged to `main` (only on the unmerged
`feat/secrets-store-openbao` branch) — checked directly rather than
assumed. Rather than wait on it, or bring in a second Crossplane provider
(`provider-sql`) that would still need the same runtime-secret bridge for
its own `ProviderConfig`, this ADR adds a purpose-built one-shot Job:

- **`database/aws-rds`** gains a fourth IAM role, `secret_reader`, scoped
  to `secretsmanager:GetSecretValue` on `secret:rds!*` — read-only,
  engine-agnostic like the KMS key and security group (any database,
  however created, needs this same step; it isn't a Crossplane concept).
  Its Pod Identity association targets a *fixed* identity,
  `system-provisioning/rds-secret-reader`, not one per consumer — the job
  always runs there regardless of which application namespace it
  publishes into, since cross-namespace publication is a Kubernetes RBAC
  question, not an AWS IAM one.
- **`kustomize/provisioning/resources/crossplane/aws-rds/`** creates that
  `ServiceAccount`, alongside the `ProviderConfig`/tag policy it already
  ships — a shared, core-provided identity multiple consumers can reuse.
- **The consuming namespace opts in.** `kustomize/demo/resources/database/rds/`
  grants `system-provisioning/rds-secret-reader` `create`/`update` on
  `Secret`s via a `Role`/`RoleBinding` the *chart* authors, not core
  reaching into a namespace uninvited. `Instance` itself is cluster-scoped
  (`rds.aws.upbound.io` has no namespaced kinds), so reading the one named
  `Instance` needs a `ClusterRole`/`ClusterRoleBinding` instead — still
  scoped by `resourceNames` to that single object. Any real chart wanting
  this pattern brings the identical `Role`/`RoleBinding` into its own
  namespace and its own named `ClusterRole`/`ClusterRoleBinding` pair.
- **The job** (`provision-app-role-job.yaml`) runs in `system-provisioning`
  in three steps: an init container polls the `Instance` until Ready,
  reads its `masterUserSecret[0].secretArn` and `address`, and resolves
  the admin credential from Secrets Manager; a second init container
  connects with `psql` as the admin user and idempotently
  (`IF NOT EXISTS` / `ALTER ROLE`, safe to rerun) creates `demo_app` with
  `SELECT`/`INSERT`/`UPDATE`/`DELETE` on the `demo` database only — no
  DDL, no other database, no superuser; the main container publishes the
  generated password as `demo-db-app-credentials` in `demo-database`,
  which the application consumes with an ordinary `secretKeyRef`, the
  same shape CNPG's own generated secret already has. Images
  (`alpine/k8s`, `postgres:16-alpine`) are digest-pinned per this repo's
  own convention; chosen specifically because both bundle a real shell
  (`bash`) and the exact tools needed (`kubectl`+`aws`+`jq`, `psql`) —
  `rancher/kubectl`, considered first, is a scratch image with no shell
  at all and can't run a wait loop.
- `Instance.spec.forProvider.dbName` was unset before this — found while
  designing the job's own `GRANT ... ON DATABASE demo`: with no `dbName`,
  Postgres RDS creates no user database beyond the built-in `postgres`,
  so there was nothing to scope `demo_app`'s grants to at all.

**IAM database authentication** (`iamDatabaseAuthenticationEnabled`) is a
stronger alternative worth naming: an application authenticates with a
short-lived token derived from its own Pod Identity role instead of a
password at all, no secret to rotate or leak. Not adopted here because it
changes the application's own connection code (most AWS SDKs support the
token flow natively, but it's not a drop-in for something expecting a
plain password), where this job's approach needs nothing from the
application beyond reading a `Secret` the same way CNPG's app secret
already works. Worth adopting per-application once that's viable, not a
blocking prerequisite for this ADR.

**The job is one-shot, deliberately.** It doesn't re-run if `demo-db` is
ever deleted and recreated (`demo_app` and its grants go with the old
instance, nothing re-triggers), and it doesn't rotate `demo_app`'s
password on any schedule — only the admin credential rotates, via AWS.
The natural fix for both is a `CronJob` instead of a `Job`, reusing the
same already-idempotent script — but a periodically-rotated `Secret`
reopens the same problem discussed earlier for ESO: updating a `Secret`
object doesn't propagate to a running pod's env vars, so rotation without
a `Reloader`-style companion just breaks the app silently on whatever
interval gets picked. Deliberately out of scope here — this ADR proves
the CNPG-parity pattern works, not a rotation platform. Recovering from
an instance recreation today means manually deleting the Job so Flux
(with `kustomize.toolkit.fluxcd.io/force: enabled`) recreates it.

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
- `network/aws-vpc`'s DB subnet group is the first real consumer of the
  isolated (zero-egress) subnet tier — it existed, unused, before this
  ADR. Created unconditionally alongside the subnets themselves, on every
  AWS context regardless of `database.postgres.driver`, the same way the
  subnets already are — not gated the way the KMS key and IAM/Pod-Identity
  wiring are, since it costs nothing idle and a subnet group with no
  databases pointed at it is inert.
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
- `crossplane-iam`'s catalog stays a plain `for_each` over its own
  `resources` set even after moving to a top-level layer — unlike every
  *other* addon's Pod Identity role in `cluster/aws-eks/main.tf`
  (cert-manager, aws-lb-controller, cluster-autoscaler, Karpenter), which
  stay flat, one block each, since none of those are a family of similar
  resources expected to grow the way Crossplane's provider pods are. The
  `database/aws-rds` KMS key, by contrast, dropped the equivalent
  catalog/`for_each` indirection entirely once it moved out — it's one
  key, not a family, so the abstraction wasn't earning its keep there,
  only for the IAM piece.
- This split moved five resources that already existed live in
  `aws-test`'s `cluster` state (the IAM role/policy/attachment, the Pod
  Identity association, the DB subnet group) into two different state
  files. `moved {}` blocks only relocate addresses within one root
  module's state; across separate Terraform states, `windsor plan` shows
  these as destroy-then-create rather than an in-place move. Safe here
  because none of the five carry a lifecycle of their own and the
  dedicated CMK this ADR's earlier revision added had never actually been
  applied — nothing was encrypted under a key a destroy-and-recreate would
  orphan. That won't stay true forever: once a real Crossplane-managed
  `Instance` is encrypted under a key this repo manages, a restructuring
  like this one needs real state surgery first, not a plan-and-apply.
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
- §7's bootstrap job is unverified against a live cluster, unlike
  everything else in this ADR — every prior fix here (subnet group ARN,
  service-linked role, both KMS gaps) was root-caused from a real
  failure, not designed ahead of one. `kubectl`/`psql` behavior, RBAC
  scoping, and the job's own retry timing are all correctness-by-review
  right now, not correctness-by-observation. Expect at least one more
  round of live-discovered fixes before this is proven, the same as
  everything else in this sequence was.

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

**A nested submodule under `cluster/aws-eks/modules/`, not a top-level
layer.** This ADR's first version put all of RDS's support infra —
IAM/Pod-Identity, the KMS key, the DB subnet group — in
`cluster/aws-eks/modules/crossplane-iam` and `main.tf` directly, on the
reasoning that no existing layer was addon-scoped and a Pod Identity
association is inherently EKS-cluster-scoped. Both turned out wrong on
inspection: `pki/ca` and `dns/zone/route53` already are addon-scoped
top-level layers, and being EKS-cluster-scoped only meant Pod Identity
needed the cluster's *outputs*, not that it had to live inside the
cluster's own module — the same relationship `dns-zone` already has to
`cluster`. Superseded by §3's three-way split once that was clear.

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
  `crossplane-iam` follows.
- [pki/ca](../../terraform/pki/ca), [dns/zone/route53](../../terraform/dns/zone/route53)
  — the addon-scoped, top-level-Terraform-layer precedent `database/aws-rds`
  and `provisioning/crossplane-iam` both follow.
- [ADR-0004](0004-external-secrets-operator.md) — the other
  install-only-controller precedent in this sequence.
- `kustomize/crds/sources.yaml` — the `crossplane` vendor entry and the
  `urls:` mode precedent (`keycloak`) it follows.
- [core#2584](https://github.com/windsorcli/core/issues/2584) — bringing
  the other 7 Pod Identity roles in `cluster/aws-eks/main.tf` up to
  `crossplane-iam`'s trust-policy scoping.
- Crossplane: [crossplane.io](https://crossplane.io). provider-aws-rds
  (Upbound): [marketplace.upbound.io/providers/upbound/provider-aws-rds](https://marketplace.upbound.io/providers/upbound/provider-aws-rds).
