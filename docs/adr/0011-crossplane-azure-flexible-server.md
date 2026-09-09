---
title: "ADR-0011: Crossplane — Azure Database for PostgreSQL Flexible Server"
description: Adds database.postgres.driver — flexibleserver, installing Crossplane's provider-azure-dbforpostgresql so a Helm chart installed on top of core can request an Azure-managed Postgres database, the same posture ADR-0009 built for AWS. Extends the fast-follow ADR-0009 §5 named but left undecided.
---

# ADR-0011: Crossplane — Azure Database for PostgreSQL Flexible Server

## Status

Proposed. Extends [ADR-0009](0009-crossplane-cloud-databases.md), whose §5 named this
as a fast-follow needing its own identity story and left it undecided. Tracked
under [core#2515](https://github.com/windsorcli/core/issues/2515), the same
umbrella issue ADR-0009 partially closed.

## Context

ADR-0009 gave AWS a way for a chart installed after `windsor apply` to request
a real cloud-managed Postgres database without authoring its own blueprint:
`database.postgres.driver: rds` installs Crossplane and `provider-aws-rds`,
wires AWS credentials through EKS Pod Identity, and a chart creates the
`Instance` CR directly. This ADR gives Azure the same capability, following
the same architecture everywhere Azure's own mechanisms genuinely match AWS's,
and departing from it only where they don't.

AKS already carries the piece ADR-0009 had to build from scratch for EKS:
Workload Identity. `cluster/azure-aks` provisions it for cert-manager and
external-dns today (`azurerm_user_assigned_identity` +
`azurerm_federated_identity_credential` + `azurerm_role_assignment`,
`oidc_issuer_enabled`/`workload_identity_enabled` both default `true`). The
identity story ADR-0009 §5 flagged as undecided is a wiring problem here, not
a research one.

## Decision

### 1. `database.postgres.driver: flexibleserver` — a third enum value

```yaml
database:
  postgres:
    enabled: true
    driver: flexibleserver   # cloudnativepg | rds | flexibleserver
```

Named for the Azure product (`Microsoft.DBforPostgreSQL/flexibleServers`),
matching `rds` naming the AWS product rather than the cloud
(`azure-postgres` was considered and rejected — `rds` carries no `aws-`
prefix either; which cloud a driver requires is already a schema
cross-field constraint, not part of the enum value itself). It also matches
Crossplane's own CRD `Kind: FlexibleServer` verbatim, so the enum value and
the resource a chart creates read as the same name. A new schema `allOf`
constraint requires `platform: azure`, mirroring `rds`'s `platform: aws`
requirement exactly.

### 2. `kustomize/provisioning/install/crossplane/azure-postgres/` — same install shape, Azure's own provider

```
install/crossplane/azure-postgres/
  provider.yaml                  # provider-azure-dbforpostgresql, digest-pinned
  provider-family-azure.yaml     # explicit dependency, digest-pinned, matching provider-family-aws
  deployment-runtime-config.yaml # pins the pod's ServiceAccount name + Workload Identity pod label
```

`provider-azure-dbforpostgresql` (group `dbforpostgresql.azure.upbound.io`,
resources `FlexibleServer`, `FlexibleServerDatabase`,
`FlexibleServerConfiguration`, `FlexibleServerFirewallRule`) is an in-family
provider of `provider-family-azure`, the same split ADR-0009 already found
for `provider-aws-rds`/`provider-family-aws` — declared explicitly and
digest-pinned for the same reason: `skipDependencyResolution: true` on the
leaf provider so Crossplane doesn't auto-resolve an unpinned copy of its
family dependency.

`DeploymentRuntimeConfig` does two jobs here where AWS's did one. It still
pins `serviceAccountTemplate.metadata.name: provider-azure-dbforpostgresql`
so Terraform's federated identity credential has a known subject to target.
It additionally has to add the pod label
`azure.workload.identity/use: "true"` (`podTemplate.metadata.labels`) and the
ServiceAccount annotation `azure.workload.identity/client-id: <clientId>` —
AKS's Workload Identity webhook only injects the
`AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_FEDERATED_TOKEN_FILE` env vars
into pods carrying that label, unlike EKS Pod Identity, which mutates any pod
running under an associated ServiceAccount with no extra opt-in label. The
client ID substitutes from `terraform_output('crossplane-identity-azure',
'client_id')`, the same `substitutions:` path `cluster_name` already takes
into the tag policy.

Crossplane's own CRDs are already vendored (ADR-0009 §2); this needs no new
CRD vendoring of its own.

### 3. Support infra splits the same three ways, by Azure's own mechanisms

**`network/azure-vnet`** gains a delegated subnet — `azurerm_subnet` with a
`delegation` block for `Microsoft.DBforPostgreSQL/flexibleServers` — created
unconditionally alongside the existing public/private/isolated tiers, the
direct analog of `aws_db_subnet_group.main`. Flexible Server's VNet-integrated
mode needs a subnet delegated to it specifically; it cannot share the
existing `isolated` subnet, which carries no delegation and is meant to stay
generic. Unconditional for the same reason the AWS subnet group is: it costs
nothing idle, and every context gets it regardless of
`database.postgres.driver`.

**`database/azure-postgres`**, a new top-level layer, owns everything
specific to running Postgres on Azure but not to Crossplane's own identity:

- A dedicated resource group (`<context_id>-postgres`) scoping both the
  `FlexibleServer`'s own placement and the identity's role assignment below —
  Azure's replacement for AWS's per-resource tag condition (§6).
- The private DNS zone Flexible Server's VNet-integrated mode requires for
  name resolution, and its VNet link. Unlike AWS's DB subnet group, this
  isn't a resource RDS is indifferent to — Flexible Server refuses to
  provision without one. Owned here, not `network`, because it's naming
  infrastructure for this one engine, the same reasoning that put the KMS
  key alias in `database/aws-rds` rather than `network/aws-vpc`.
- An NSG on the delegated subnet, allowing Postgres (5432) from the AKS node
  subnet's CIDR. Azure NSGs match by CIDR or Application Security Group
  membership, not by referencing another resource's security-group ID the
  way `aws_security_group.rds`'s ingress rule references EKS's cluster
  security group directly — the closest available analog, still scoped to
  the cluster's own subnet rather than the whole VNet address space.
- Customer-managed key encryption, same BYOK precedence `aws-rds` already
  established: an explicit Key Vault key ID
  (`database.postgres.encryption.key_vault_key_id`) wins if set; otherwise
  Flexible Server's platform-managed encryption applies with no Key Vault at
  all, since (unlike RDS) Azure needs no dedicated-key step to get an
  encrypted-at-rest default — there is no AWS-managed-key-equivalent
  IAM/KMS grant dance to redo here.

**`provisioning/crossplane-identity-azure`**, a new top-level layer, owns the
identity Crossplane's `provider-azure-dbforpostgresql` pod authenticates as:
a `azurerm_user_assigned_identity`, its
`azurerm_federated_identity_credential` (issuer
`cluster/azure-aks`'s `oidc_issuer_url` output, subject
`system:serviceaccount:system-provisioning:provider-azure-dbforpostgresql`,
matching the fixed ServiceAccount name §2 pins), and a role assignment
scoped to the resource group `database/azure-postgres` creates.

Named `crossplane-identity-azure`, not `crossplane-iam-azure` — Azure's own
mechanism is Workload Identity, not IAM; reusing AWS's vocabulary here would
misname what it is, the same reasoning ADR-0009 §2 gave for not nesting
Crossplane's install under `kustomize/database/`. Kept as its own layer
rather than folding into the existing `provisioning/crossplane-iam` (an
`azurerm`/`aws` provider mix isn't expressible in one Terraform root module
anyway), so the AWS layer's name stays as ADR-0009 left it — no rename, no
state migration for a module nothing here touches.

Azure has no analog to AWS's `aws:RequestTag`/`aws:ResourceTag` IAM
condition — Azure RBAC's ABAC condition support (`role_definition` `condition`
blocks) is scoped to a handful of resource providers (Storage Blob Data among
them) and does not cover `Microsoft.DBforPostgreSQL` as of writing;
**verify this before relying on it, it's a load-bearing assumption**. Absent
a tag condition, `crossplane-identity-azure`'s role assignment scopes to the
dedicated resource group instead — Azure's own natural blast-radius
boundary — via a custom `azurerm_role_definition` (not the built-in
`Contributor`) granting exactly `Microsoft.DBforPostgreSQL/flexibleServers/*`,
`.../flexibleServers/databases/*`, `.../flexibleServers/configurations/*`,
plus the two narrow network actions Flexible Server's own creation needs:
`Microsoft.Network/virtualNetworks/subnets/join/action` (attaching the
delegated subnet) and `Microsoft.Network/privateDnsZones/join/action`
(linking the private DNS zone) — RG-scoped, action-scoped, matching the
precision of AWS's policy without a tag condition to fall back on.

### 4. The chart creates two Crossplane resources directly, not one

No core-authored claim CRD, matching ADR-0009 §4's stance exactly. Where RDS's
`Instance` carries its own default database via `spec.forProvider.dbName`,
Flexible Server has no such field — the server and its database are two
separate CRs. A chart creates a `dbforpostgresql.azure.upbound.io
FlexibleServer` and a `dbforpostgresql.azure.upbound.io
FlexibleServerDatabase` referencing it, both directly, the same posture as
CNPG's `Cluster` and RDS's `Instance`. This is a real shape difference from
RDS worth naming, not a gap: nothing in this ADR's design depends on the
database existing at server-creation time the way `dbName` did for RDS's app
role provisioning (§6 below reads the database name from the
`FlexibleServerDatabase` CR the chart creates, not from the server).

### 5. Network access stays non-public, Azure's own way

`FlexibleServer.spec.forProvider.publicNetworkAccessEnabled: false` plus
`delegatedSubnetId`/`privateDnsZoneId` referencing §3's subnet and zone puts
the server inside the VNet with no public endpoint at all — the Azure
equivalent of RDS's `publiclyAccessible: false` plus an empty-by-default
security group. The delegated subnet's NSG (§3) is the actual traffic gate;
maintenance and developer access follow ADR-0009 §6's precedent unchanged —
a temporary in-cluster pod plus `kubectl port-forward`, no bastion, no VPN.

### 6. Application credentials, and less machinery than AWS needed

Flexible Server has no `manageMasterUserPassword`-equivalent auto-generated
secret in a cloud secret store. Crossplane's own field does the equivalent
job more directly: `administratorPasswordSecretRef` (name/namespace/key of a
Kubernetes `Secret`) combined with `autoGeneratePassword: true` has
Crossplane itself generate the admin password and write it straight into
that `Secret` if it doesn't already hold one — no Key Vault involved, no
cloud API round-trip to fetch it later.

That collapses a whole tier of ADR-0009's design. RDS needed a dedicated
`secret_reader` IAM role and Pod Identity association purely to call
`secretsmanager:GetSecretValue`, because the master password lived in AWS
Secrets Manager, reachable only through that IAM grant. Here, the admin
credential is already a Kubernetes `Secret` in `system-provisioning` — the
bootstrap CronJob reads it with an ordinary `secretKeyRef`, no IAM/RBAC
identity dedicated to reading it at all.

The rest of ADR-0009 §7's design carries over unchanged, including its own
ownership correction: the CronJob (not a `Job`, same idempotent-rerun
reasoning) provisions `<db>_app` from the admin credential — never handing
the admin credential itself to a consumer — makes it the *owner* of its
database (`ALTER DATABASE <db> OWNER TO <db>_app`, matching CNPG's own
default `app` user, so the chart can run its own schema migrations), and
publishes `<flexibleserver_name>-app-credentials`.
`kustomize/provisioning/resources/crossplane/azure-postgres/app-role` takes
the same three required substitutions (`pg_instance_name`,
`pg_database_name`, `pg_target_namespace`) plus the same optional
`pg_grant_sql`, for anything ownership doesn't cover. The password-reuse fix
ADR-0009 found live (reuse an already-published `Secret`'s password rather
than regenerating on every tick) applies identically — it isn't RDS-specific,
it follows from the `Secret`-read-once-at-pod-start problem either engine
has.

**Resource-group scoping, not a tag policy.** ADR-0009's `crossplane-rds-tag`
Kyverno policy force-sets the tag the RDS IAM policy conditions on. Azure's analog,
`crossplane-flexibleserver-rg`, force-sets `resourceGroupName` (a
`spec.forProvider` field on the CR itself, not a tag) to
`database/azure-postgres`'s dedicated resource group on every submitted
`FlexibleServer` — `failurePolicy: Ignore`, same fail-open stance, since §3's
RG-scoped role assignment is the backstop that rejects a wrongly-scoped
create either way.

### 7. Observability reuses CNPG's own dashboard, unchanged

Unlike §6, this section needs almost no new design. `postgres_exporter`
speaks Postgres, not RDS or Flexible Server — the exporter, its metric
vocabulary, the Grafana dashboard, and the `ConfigMap`+sidecar delivery
ADR-0009 §8 built are entirely engine-agnostic once something publishes a
connection string. The only new work is the same Kyverno `generate` shape
§6 already establishes, retargeted: a `pg_monitor` role provisioned the same
way the app role is (from the admin `Secret`, no cloud API), and the
exporter `Deployment`/`Service`/`PodMonitor` generated against `FlexibleServer`
creates instead of `Instance` creates. `kustomize/observability/resources/
grafana/dashboards/postgres-exporter` needs no Azure-specific variant; the
existing `driver == 'rds' || driver == 'flexibleserver'` condition in
`addon-database.yaml`'s `observability` entry selects it for either cloud.
`kustomize/telemetry/resources/prometheus/alerts/postgres-exporter` carries
over the same way — its rules are PromQL against the exporter's own metrics,
with no engine opinion to begin with.

### 8. Demo wiring mirrors `kustomize/demo/resources/database/rds`

`kustomize/demo/resources/database/flexibleserver/` holds the worked example
— a `FlexibleServer` and `FlexibleServerDatabase`, no provider wiring, the
same contract `rds/instance.yaml` documents. `option-demo.yaml` gains the
Azure-driver twin of its existing `demo-database`/`demo-app-role` entries,
gated on `database.postgres.driver == 'flexibleserver'` instead of `'rds'`,
substituting `terraform_output('database', ...)` and
`terraform_output('crossplane-identity-azure', ...)` outputs the same way.

## Consequences

- A second Crossplane-managed Azure resource type (object storage, say) adds
  its own `install/crossplane/<provider>` + `resources/crossplane/<provider>`
  pair and its own entry in `crossplane-identity-azure`'s resource catalog —
  the same extension point ADR-0009's Consequences section already
  documented for AWS.
- §6's simplification (no cloud secret-store bootstrap tier) means Azure's
  app-role/monitor-role CronJobs have one fewer moving part than RDS's, and
  one fewer IAM/RBAC identity to reason about. Nothing about this ADR forces
  parity with AWS's exact mechanics where Azure's own are simpler.
- §6's ownership transfer (`ALTER DATABASE ... OWNER TO <db>_app`) needs its
  own live check: the admin role Flexible Server creates has to actually be
  able to reassign ownership to a role it just created, the same assumption
  ADR-0009's own correction (its Consequences section) flags as unverified
  for RDS. Nothing here suggests Flexible Server's admin role behaves any
  differently, but neither ADR has run this against a live cluster yet.
- The custom `azurerm_role_definition` this ADR proposes (§3) needs the
  exact Azure action strings verified against a live subscription before
  implementation — `Microsoft.DBforPostgreSQL`'s action namespace, and
  whether the two network `join/action` grants are sufficient for Crossplane
  to attach the delegated subnet and link the private DNS zone, are asserted
  here, not yet confirmed live the way ADR-0009's AWS policy was.
- Whether Azure RBAC's ABAC condition support extends to
  `Microsoft.DBforPostgreSQL` needs the same live check (§3) — if it does,
  the resource-group-scoping design here could tighten to per-resource
  conditions closer to AWS's, though RG scoping is a reasonable permanent
  choice on its own, not merely a workaround.
- `FlexibleServerDatabase` being a separate CR from `FlexibleServer` (§4)
  means the demo and any documented chart contract creates two resources,
  not one — a one-time source of confusion for anyone used to RDS's
  single-CR shape, worth calling out plainly in
  `kustomize/provisioning/README.md` when this lands.
- None of this has been run against a live AKS cluster yet. Every mechanism
  described — the Workload Identity federation, the delegated-subnet +
  private-DNS-zone requirement, `administratorPasswordSecretRef` +
  `autoGeneratePassword`, the custom role's action set — is asserted from
  provider documentation and Azure's own reference docs, not verified live
  the way ADR-0009's design was proven end-to-end before being written up.
  Treat this ADR's Decision section as a starting implementation plan, and
  update it with what's actually found once `windsor apply` runs against it,
  the same way ADR-0009 records its own live corrections.

## Alternatives considered

**Reuse `provisioning/crossplane-iam` for both clouds.** Rejected: an
`azurerm` and `aws` provider can't share one Terraform root module's
provider block, and Azure's role-assignment/identity resources don't map
onto an AWS-shaped `for_each` catalog without contorting one to fit the
other. Two layers, sharing only the `provisioning` kustomize domain name
(already generic per ADR-0009 §2), costs nothing a shared module would have
saved.

**`azure-postgres` as the driver enum value, cloud-prefixed.** Rejected in
§1 for the same reason `rds` carries no `aws-` prefix: which cloud a driver
needs is a schema constraint, not part of the value's own name.

**Azure AD (Entra ID) authentication instead of a generated admin
password.** Would drop the admin-password `Secret` entirely — `provider-azure-
dbforpostgresql` supports Entra-only auth via
`spec.forProvider.authentication.activeDirectoryAuthEnabled`. Not adopted
here for the same reason ADR-0009 §7 didn't adopt RDS's equivalent IAM
database authentication for v1: it changes what a consuming application's
connection code has to do, where this ADR's approach needs nothing beyond
reading a `Secret`, matching CNPG's own app-secret shape. Worth adopting
per-application later, not a blocking prerequisite here either.

## References

- [ADR-0009](0009-crossplane-cloud-databases.md) — the AWS design this ADR
  extends; every section number above corresponds to its equivalent section
  there.
- [core#2515](https://github.com/windsorcli/core/issues/2515) — the umbrella
  issue both ADRs scope down.
- [cluster/azure-aks main.tf](../../terraform/cluster/azure-aks/main.tf)
  (`azurerm_user_assigned_identity.cert_manager`, `.external_dns`) — the
  Workload Identity pattern `crossplane-identity-azure` follows.
- [database/aws-rds](../../terraform/database/aws-rds),
  [provisioning/crossplane-iam](../../terraform/provisioning/crossplane-iam)
  — the layer split this ADR's `database/azure-postgres` and
  `provisioning/crossplane-identity-azure` mirror.
- Crossplane Workload Identity guide:
  [docs.crossplane.io/latest/guides/crossplane-with-workload-identity](https://docs.crossplane.io/latest/guides/crossplane-with-workload-identity/).
- provider-azure-dbforpostgresql (Upbound):
  [marketplace.upbound.io/providers/upbound/provider-azure-dbforpostgresql](https://marketplace.upbound.io/providers/upbound/provider-azure-dbforpostgresql).
