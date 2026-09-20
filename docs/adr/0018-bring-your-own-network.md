---
title: "ADR-0018: Bring-your-own network — adopting an existing VPC, VNet, or GCP network"
description: Adds a network.existing block whose presence selects sibling terraform/network/<cloud>-data modules that read a customer-owned network through data sources and emit the same outputs as the create modules. Component identity is the facet `name:`, so no consumer expression changes and no CLI change is needed.
---

# ADR-0018: Bring-your-own network — adopting an existing VPC, VNet, or GCP network

## Status

Proposed. Replaces the backlog note in
[roadmap-v0.8.0.md](roadmap-v0.8.0.md) that recorded this work as blocked
on a `cli`-side expression-evaluable `path:` field. It is not blocked;
§2 explains why.

## Context

Every cloud platform facet creates its own network. `platform-aws`
declares `network` at `network/aws-vpc`, `platform-azure` at
`network/azure-vnet`, `platform-gcp` at `network/gcp-vpc`, and each
module builds the VPC, three subnet tiers, NAT, and optionally a private
DNS zone from scratch.

Plenty of prospective users cannot accept that. A central network team
already owns the VPC, its CIDR allocation came out of an IPAM process,
and the subnets are peered or transit-attached to the rest of the
estate. Windsor creating another VPC beside all that is not something
they can approve. They want Windsor to land a cluster inside the
network they already run.

Nothing in core supports this today. None of the three network modules
accepts an existing network identifier; they all create.

## Decision

### 1. A `network.existing` block, selected by its presence

```yaml
network:
  existing:
    id: vpc-0a1b2c3d4e5f
    subnets:
      public:   [subnet-0aaa, subnet-0bbb]
      private:  [subnet-0ccc, subnet-0ddd]
      isolated: [subnet-0eee, subnet-0fff]
    database_subnet: ""     # Azure only
    pod_range: ""           # GCP only
    service_range: ""       # GCP only
```

The three trailing fields are the entire per-cloud surface, and each is
documented with the cloud that reads it. They exist because the clouds
do not agree on where pod addresses come from, which §"What a customer
network must provide" works through.

Set `network.existing.id` and Windsor reads that network. Leave the
block out and Windsor creates one, which is what it does today.

There is no mode enum. Windsor already selects between creating and
attaching this way: `hyperv.net_adapter` creates an External switch
when set and uses an Internal one when unset, and the facets gate on
`(network.cidr_block ?? '') == ''` throughout. Presence of the
identifying field is the house idiom, and `existing` is the same word
Helm charts use for the identical question in `existingSecret` and
`existingClaim`.

A `driver` enum would have been the wrong word. Every other `driver` in
the schema picks an implementation among vendors: `metallb` or
`kube-vip`, `keycloak` or `oidc`. Who owns the network's lifecycle is a
different kind of question, and answering it with a driver enum would
have put a non-vendor value in a field that otherwise always holds one.

Presence-based selection risks a typo creating a VPC in an account that
forbids exactly that. The `network` block already sets
`additionalProperties: false`, so a misspelled key fails schema
validation instead of falling through to the create path. What schema
validation cannot catch is a half-filled block, so a `requires:` covers
it:

```yaml
requires:
  - when: (network.existing.id ?? '') != ''
    paths:
      - network.existing.subnets.private
    message: Deploying into an existing network needs the subnets to place cluster nodes in.
```

### 2. Two components, one name

A facet selects the module with a second component sharing the same
`name:`:

```yaml
  - name: network
    when: (network.existing.id ?? '') == ''
    path: network/aws-vpc
    dependsOn:
      - backend
    inputs: { ... }

  - name: network
    when: (network.existing.id ?? '') != ''
    path: network/aws-vpc-data
    dependsOn:
      - backend
    inputs:
      vpc_id: ${network.existing.id}
      public_subnet_ids: ${network.existing.subnets.public ?? []}
      private_subnet_ids: ${network.existing.subnets.private ?? []}
      isolated_subnet_ids: ${network.existing.subnets.isolated ?? []}
```

This works today. `TerraformComponent.GetID()` returns `Name` when set
and falls back to `Path` only when it is empty, so component identity
is the name and the path is free to vary. `collectTerraformComponents`
evaluates each component's `when:` and skips excluded components before
the ID map insert, so the two declarations never collide.
`option-workstation` already ships this exact pattern for `name:
compute` across `compute/incus` and `compute/docker`, and has since
75d2a6c1c in February 2026. Core declares `cliVersion: ">=0.9.0"` in
`contexts/_template/metadata.yaml`, so every CLI core supports already
composes it; a CLI that could not would have broken `compute` long
before this ADR.

Two constraints follow. The conditions MUST be mutually exclusive,
because two surviving components with one ID would merge by ordinal and
strategy and produce a component with one module's path and the other's
inputs. And a component-level `when:` replaces the facet-level
condition rather than combining with it, so these conditions MUST NOT
be written as if the facet's `platform == 'aws'` gate still applied to
them — it does not, though the facet gate already ran, so repeating it
is unnecessary.

Every consumer expression stays byte-identical.
`terraform_output('network', 'vpc_id')` in `platform-aws.yaml`,
`addon-database.yaml`, and `option-demo.yaml` resolves by name and never
learns which module ran.

### 3. Sibling `-data` modules with an identical output contract

Each create module gains a sibling: `network/aws-vpc-data`,
`network/azure-vnet-data`, `network/gcp-vpc-data`. The sibling reads the
customer's network through data sources and emits the same output names
with the same types.

The contract is not negotiable per module, because the consumers are
already written. Today's facet-visible surface is:

| Cloud | Outputs consumed by facets |
|---|---|
| AWS | `vpc_id`, `private_subnet_ids`, `db_subnet_group_name`, `private_zone_id` |
| Azure | `vnet_id`, `region`, `subscription_id`, `resource_group_name`, `private_subnet_ids`, `private_subnet_cidrs`, `azuredb_subnet_id`, `private_zone_id` |
| GCP | `network_id`, `region`, `private_subnet_id`, `available_zones` |

The data modules MUST emit the create modules' full output set, not just
the consumed subset, so that a later facet referencing
`isolated_subnet_ids` does not break only for users who adopt a network.

### 4. Fully-qualified identifiers carry the per-cloud scoping

`network.existing.id` is one field across three clouds that need different
amounts of context, which works because each cloud's canonical
identifier already encodes what that cloud needs.

Azure's VNet resource ID is
`/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<name>`,
so `subscription_id` and `resource_group_name` are parsed out of it
rather than configured separately. The create module already does this:
`subscription_id = element(split("/", azurerm_virtual_network.main.id), 2)`
in `terraform/network/azure-vnet/outputs.tf`.

GCP's network ID is `projects/<project>/global/networks/<name>`. For a
Shared VPC the `<project>` is the host project, which differs from
`gcp.project_id`. Parsing it out of `network.existing.id` gives Shared VPC
support with no additional schema field.

AWS's `vpc-0a1b2c3d` carries nothing, and needs to carry nothing, since
the region comes from `aws.region` and the account from the provider's
caller identity.

So the schema stays uniform and the per-cloud data module absorbs the
difference. That is the general principle for the rest of this design.

### 5. Subnet tiers are the mapping surface

Windsor's taxonomy is public, private, isolated: internet-facing load
balancers, cluster nodes, and databases with no egress. A customer's
network will not share that vocabulary, and many have only two tiers.
`network.existing.subnets` is where they map what they have onto what
Windsor expects, and the same subnet ID MAY appear in more than one tier
when the customer's network genuinely does not separate them.

There is no fourth `database` tier. `isolated` already is the database
tier: the AWS create module builds its DB subnet group over the isolated
subnets, and Cloud SQL on GCP takes no subnet at all. Only Azure needs a
separate identifier, and §"Cross-cloud differences" handles it as the
per-cloud exception it is rather than as a tier all three clouds would
appear to share.

GCP subnets are regional rather than zonal, so the GCP data module takes
element `[0]` of each list and ignores the rest. The schema does not
diverge for it.

`available_zones` on GCP derives from `gcp.region` exactly as the create
module derives it. On AWS the data module derives AZ placement from the
supplied subnets via `data.aws_subnet`, which also gives it the input
for the validation in §7.

### 6. What a data module MAY create

A data module MUST NOT create, modify, or delete anything the customer
owns. `windsor destroy` against an adopted network MUST leave the
network exactly as it found it.

It MAY create resources that only group or reference customer
resources without mutating them. The AWS DB subnet group is the case
that matters: `aws_db_subnet_group` is a free, RDS-scoped grouping over
subnet IDs, it changes nothing about those subnets, and creating it
keeps `db_subnet_group_name` satisfiable without asking the customer to
pre-build one. Destroying it removes the grouping and leaves the
subnets untouched.

### 7. Validation, fail-closed

The data modules MUST validate their inputs rather than passing bad
identifiers downstream, where the failure surfaces as an opaque error
from EKS or CNPG. Each module MUST verify through `precondition` or
`check` blocks that:

- every supplied subnet belongs to the supplied network
- `private` is non-empty
- AWS `private` spans at least two availability zones, matching the
  create module's `availability_zones >= 2` validation
- Azure's `network.existing.database_subnet` names a subnet that exists
  in the supplied VNet; its delegation is not checkable through the
  pinned provider and is taken on trust

### 8. An output-parity test

The long-term failure mode is drift: someone adds an output to
`network/aws-vpc`, a facet starts consuming it, and the adopted path
breaks for users who are not in CI. A CI check MUST compare the set of
`output` names declared in each create module against its `-data`
sibling and fail on any difference. This is a comparison of
`outputs.tf` declarations, cheap enough to run on every PR, and it is
the only thing keeping §3's contract honest over time.

## What a customer network must provide

The create modules build considerably more than Windsor needs. Telling
the two apart is what decides whether adoption works against a network
nobody designed for Windsor.

**The binding constraint is where pod addresses come from, and all three
clouds answer differently.**

| Cloud | CNI as configured | Pod addresses come from | So private subnet sizing is driven by |
|---|---|---|---|
| AWS | `vpc-cni` addon | the subnet itself | pods plus nodes |
| Azure | `azure` plugin, `overlay` mode, Cilium | a separate pod CIDR | nodes only |
| GCP | `VPC_NATIVE`, Dataplane V2 | secondary ranges on the subnet | the ranges, not the primary CIDR |

AWS is the demanding one. Every pod takes a real subnet address, and
Windsor's own default gives each private subnet a `/20` carved from a
`/16` with `subnet_newbits = 4`, so roughly four thousand addresses per
AZ. A customer handing over a `/26` per AZ out of a tightly managed IPAM
allocation has given Windsor about sixty addresses to hold nodes and
every pod on them. That deployment will run out of IPs under load, and
it will do so long after apply succeeds. Azure is the forgiving one,
since overlay mode means the subnet only ever holds nodes.

**What Windsor genuinely requires:**

- Outbound reachability from the node subnets to the container
  registries, by whatever mechanism the customer already uses. Windsor
  builds NAT gateways on the create path and needs none of them here.
- Private subnets in at least two availability zones on AWS. EKS
  enforces this for the control plane, and the RDS subnet group needs it
  independently, which is why the create module validates
  `availability_zones >= 2`.
- Address space consistent with the table above.
- No overlap between the customer's routed ranges and the Kubernetes
  service CIDR, which defaults to `10.96.0.0/16` on AKS. A customer
  already routing `10.96/16` on-premises gets a cluster whose service
  addresses are unreachable, and nothing in apply detects it.
- API server reachability from wherever `windsor` runs. EKS defaults to
  a public endpoint, so a customer requiring a private-only endpoint
  changes how the CLI reaches the cluster.

**What Windsor does not require, despite building it:**

- Public subnets. No facet consumes `public_subnet_ids`; the create
  module uses them for its own NAT gateways. A private-only VPC works,
  paired with `gateway.access: private`, and `subnets.public` MAY be
  empty.
- Windsor's tier vocabulary or CIDR layout. The tiers are a mapping
  surface, and one subnet MAY serve more than one tier.
- A particular subnet count. AWS wants two AZs; nothing else counts
  subnets.
- Flow logs, the restricted default security group, or the private DNS
  zone. Each is a create-path opinion, and adopting a network hands all
  three to the customer.

**What will fail, and how visibly:**

| Situation | Failure |
|---|---|
| AWS private subnets too small for pod count | Apply succeeds; pods go `Pending` on IP exhaustion later |
| Customer routes overlap the service CIDR | Apply succeeds; service addresses silently unreachable |
| No secondary ranges and no permission to create them on GCP | GKE creation fails |
| Azure database subnet missing its delegation | Azure rejects the Flexible Server at apply |
| Subnet not in the named network | Caught at plan by §7 |
| No egress path from the node subnets | Nodes join, images never pull |

The first two are the ones worth designing against. The rest fail
loudly enough to debug.

## Making the silent failures loud

It is tempting to accept the first two rows on the grounds that anyone
adopting a VPC understands their own network. That defense is half
right, and the half that fails is structural rather than a question of
competence.

Adoption exists because a central network team owns the VPC. So the
person who knows the IPAM allocation and the person running `windsor
apply` are usually not the same person, and what passes between them is
a ticket carrying a VPC ID and a list of subnet IDs. "EKS runs the VPC
CNI, so every pod consumes a subnet address, so a `/26` per AZ caps this
cluster near sixty pods" is a fact that needs both halves at once. The
network team has no reason to know which CNI Windsor configures. The
platform engineer has no reason to have looked up the prefix length.
Neither is being careless.

So the job is not to teach networking. It is to do that one
translation, mechanically, at a point where it still costs nothing. Both
rows can be caught.

**Subnet capacity.** `data.aws_subnet` exposes
`available_ip_address_count`. Windsor knows the requested node count
from `cluster.pools`. Pods per node under the VPC CNI varies by instance
type, but catching this does not need precision, because the failing
cases are off by an order of magnitude rather than a few percent.
Comparing available addresses against nodes times a conservative pods
per node, and putting the arithmetic in the error message, turns a
`Pending` pod three weeks later into a failed plan.

**Routed-range overlap.** Checking the service CIDR against the VPC CIDR
is the obvious move and it is too narrow, because the ranges that
actually collide usually arrive over a transit gateway or a peering
connection rather than sitting inside the VPC. The subnets' route tables
enumerate exactly what is routed. Reading them through
`data.aws_route_table` and testing the service and pod CIDRs against
every destination catches the on-premises `10.96/16` case that a VPC
CIDR comparison misses entirely.

**Where the checks live.** Not in the data modules. §6 makes them
readers, and feeding cluster intent backwards into the network layer to
validate against would undo that. Instead each network module, on both
paths, emits the diagnostics as ordinary outputs: per-subnet available
addresses, and the set of routed destination CIDRs. The assertions then
sit downstream in the cluster module, where node counts and the service
CIDR already are, written as the `terraform_data` plus
`lifecycle.precondition` pattern `cluster/talos` and `compute/incus`
already use.

Three properties fall out of that placement. The diagnostics are part of
the output contract, so §8's parity test covers them and they cannot
drift between the create and data modules. The create path gets the same
checks for free, which is worth having, since Windsor's own `/20`
default is generous but `cluster.pools` can still outgrow it. And the
network component depends only on `backend` and, when adopting, creates
nothing, so a failed precondition downstream of it lands before any
billable resource exists.

**What stays genuinely unfixable.** Two things, and both MUST be
documented rather than designed around. A customer can change the
network after adoption, and Windsor reads it only when it runs, so a
subnet removed or a route withdrawn next quarter is invisible until
something breaks. And capacity adequate at apply can be exhausted by
later growth, which no plan-time check can predict. The answer to the
second is an alert on subnet address exhaustion through the
observability stack core already ships, not a precondition pretending to
be a guarantee.

**Verified against the providers this repo pins**, by dumping
`terraform providers schema -json` from the already-initialized
`terraform/network/*` modules. No cloud account was involved.

| Assumption | Result |
|---|---|
| `data.aws_subnet.available_ip_address_count` | Present |
| `data.aws_subnet.availability_zone`, `.vpc_id` | Present; AZ-span and membership checks are writable |
| `data.aws_route_table.routes`, keyed by `subnet_id` | Present; per-subnet routed-destination enumeration works |
| `data.google_compute_subnetwork.secondary_ip_range` | Present; named pod and service ranges are readable |
| `data.google_compute_network_peering` | Present; the private services access check is writable |
| `data.azurerm_subnet` exposing `delegation` | **Absent** |

The last row cost this design a check. See below.

## Cross-cloud differences that do not fit the uniform model

Four cases need a per-cloud answer, and they are the substance of the
cross-cloud work.

**Azure requires a delegated subnet.** A VNet-injected Flexible Server
needs a subnet delegated to
`Microsoft.DBforPostgreSQL/flexibleServers`, and delegation mutates the
customer's subnet, which §6 forbids. So Azure takes one extra field,
`network.existing.database_subnet`, which MUST name an already-delegated
subnet whenever a database driver that injects into the VNet is enabled.
The field is Azure-only and the schema says so, which is the honest way
to carry a difference only one cloud has.

Windsor cannot verify the delegation. `data.azurerm_subnet` on the
pinned `hashicorp/azurerm ~> 5.4.0` exposes `address_prefixes`,
`route_table_id`, `service_endpoint` and the rest, but no `delegation`
attribute, so the property that matters is unreadable through the
provider this repo already depends on. Windsor therefore validates that
the named subnet exists and belongs to the VNet, and takes the
delegation on trust. A subnet supplied without it fails later, when
Azure rejects the Flexible Server, with Azure's own error rather than
one of ours.

Adding the `azapi` provider would make the delegation readable as raw
ARM properties. That is rejected for now: a new provider dependency
across every Azure deployment is a large price for one precondition, and
Azure's own error names the problem accurately. Revisit it if this
failure turns out to bite real users.

Customers who cannot delegate a subnet have a separate path through
Flexible Server's public-access mode, which is out of scope here.

**GCP secondary ranges cannot be assumed.** `gcp-gke` sets
`networking_mode = "VPC_NATIVE"` with an empty `ip_allocation_policy {}`,
which lets GKE create the pod and service secondary ranges on the
subnet itself. On a Shared VPC that usually fails: the host project
owns the subnet, the service project cannot add ranges to it, and the
network team pre-allocates named ranges instead. So adopting a GCP
network takes `pod_range` and `service_range`. `gcp-gke` gains two
matching variables and sets `ip_allocation_policy`'s
`cluster_secondary_range_name` and `services_secondary_range_name` from
them. When both are unset the empty block stays and Windsor keeps
today's auto-create behavior.

**GCP also requires private services access for Cloud SQL.** Private IP
depends on an allocated range plus a `servicenetworking` peering on the
VPC, both network-level mutations owned by whoever owns the network. The
data module MUST verify the peering exists and fail with a message
naming it, rather than letting Cloud SQL provisioning fail later.

**AWS load balancer subnet discovery is tag-driven.** The AWS Load
Balancer controller receives `vpc_id` and discovers subnets from
`kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` tags.
The create module does not apply those tags either, so this is not a
regression introduced by BYO, but a customer VPC is likelier to have
absent or conflicting tags and likelier to have IaC that strips tags
Windsor did not apply. The supported answer is the per-Gateway subnet
annotation rather than Windsor tagging subnets it does not own.

**Azure egress may not be Windsor's to choose.** `azure-aks` defaults
`outbound_type` to `userAssignedNATGateway`. A customer routing egress
through a firewall or NVA needs `userDefinedRouting`, which the module
already accepts as a variable but no schema field reaches. Adopting a
VNet without exposing it leaves those customers unable to deploy.

## Consequences

- Behavior without `network.existing` is unchanged. The default path adds one
  `when:` evaluation per platform facet and nothing else.
- Adopting a network moves responsibility for NAT, flow logs, default
  security group posture, and the encryption and audit baseline in
  [ADR-0008](0008-platform-hardening-parity.md) onto the customer.
  Windsor stops asserting them and MUST NOT claim them in the
  hardening matrix for contexts that adopt a network.
- The create modules' NAT, flow-log, and IAP toggles have no analogue
  on the data side, so an adopted network ignores them. They are module
  inputs rather than schema fields today, so nothing in the schema
  needs to change.
- The two silent failures become plan-time failures, at the cost of two
  diagnostic outputs per network module and preconditions in the cluster
  modules. Post-adoption drift and growth-driven exhaustion stay
  undetectable at plan time and need documentation and an alert rule
  instead.
- `windsor test` gains a second branch per cloud platform. Both branches
  of each pair need a case, since a broken `when:` on either one
  produces a composition with zero `network` components or two.
- The private DNS zone that `aws-vpc` and `azure-vnet` create from
  `domain_name` is part of the network module, so an adopted network
  drops `private_zone_id` unless the customer supplies their own. The
  data modules take an optional existing private zone ID and pass it
  through.

## Milestones

1. AWS. `network/aws-vpc-data`, the schema block, the `platform-aws`
   component pair, the output-parity check, and facet tests for both
   branches.
2. Azure and GCP. Same structure, plus the delegation check and the
   private services access check.
3. Public DNS zone. The same two-component pattern applied to the
   `dns-zone` component, selected by a `dns.public_zone.existing` block
   symmetric with `network.existing`, for customers whose registrar
   delegation already points at a zone they own.

## Alternatives considered

**An expression-evaluable `path:` field in the CLI.** The original
backlog framing. It would let one component switch modules through
`path: network/aws-vpc${(network.existing.id ?? '') != '' ? '-data' : ''}`.
It requires a `cli` change, it buys nothing over §2, and string-built
module paths are harder to read than two conditions.

**One module per cloud with an optional `vpc_id` input.** No new
components, and one path to maintain. Rejected because every resource
in the module would need a `count` conditional and every output a
`coalesce`, which is a large and permanent readability cost on the
create path that most users take, in exchange for avoiding one extra
component declaration.

**Terraform `import` of the customer's network into Windsor state.**
An `import {}` block per resource gives full output parity for free, and
`import` is the word a reviewer reaches for first. Rejected outright,
and the word is reserved rather than reused. Importing moves the
customer's VPC into Windsor's state and makes Windsor its owner, so
`windsor destroy` deletes it. That is the opposite of what adopting a
network means, and borrowing the word for the read-only case would
mislead every Terraform-literate operator who read it.

The vocabulary that fits is already in the design. Terraform calls
reading something you do not own a data source, which is why the
sibling modules are named `-data`. Create writes, `-data` reads, and no
third word is needed.

A real `import` feature would be a different capability: take over a
network the customer no longer wants to manage and own it from then on,
including deleting it on teardown. Nobody has asked for it, it is
sharp enough to deserve its own ADR, and keeping `import` unused here
leaves the word free for it.

## References

- `contexts/_template/facets/option-workstation.yaml` — the shipped
  same-name, different-path, mutually-exclusive-`when:` pattern this
  design reuses.
- `terraform/network/azure-vnet/outputs.tf` — the existing
  parse-scoping-out-of-the-resource-ID precedent behind §4.
- [ADR-0008](0008-platform-hardening-parity.md) — the hardening
  baseline that an adopted network hands to the customer.
- [ADR-0017](0017-database-network-identifier-provisioning.md) —
  defaults the cloud network identifiers Crossplane databases consume,
  which read from this component's outputs.
