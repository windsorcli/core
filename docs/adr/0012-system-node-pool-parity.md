---
title: "ADR-0012: System node pool parity across AWS, Azure, and GCP"
description: "Azure and GCP always provision a tainted system node pool independent of user pool config; AWS's only exists as a facet default that a user's own cluster.pools silently drops. No provider schedules platform-tier controllers onto the system pool it creates, and none makes it highly available under topology: ha. Closes these gaps by making AWS's system pool module-level like GCP's, tolerating/preferring the existing platform-critical component list onto system capacity, and wiring topology: ha to a 3-node system pool."
---

# ADR-0012: System node pool parity across AWS, Azure, and GCP

## Status

Proposed. Decision 1 is in review as
[PR #2719](https://github.com/windsorcli/core/pull/2719).

## Context

"System node pool" is Azure's own term: AKS has a native `mode: System` /
`mode: User` distinction, and a system-mode pool is required to host
AKS-managed critical pods (CoreDNS, metrics-server, konnectivity). AWS and
GCP have no equivalent API primitive, but the same isolation pattern —
a dedicated node pool tainted `CriticalAddonsOnly=true:NoSchedule` — is
the documented community best practice for both: the
[AWS EKS best-practices guide](https://docs.aws.amazon.com/eks/latest/best-practices/reliability.html)
recommends a dedicated node group for critical add-ons, and
[GKE's workload-isolation guide](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/isolate-workloads-dedicated-nodes)
recommends the same taint to protect GKE-managed privileged workloads.
Reusing "system" and the `CriticalAddonsOnly` taint across all three
providers extends existing ecosystem vocabulary rather than inventing a
new one.

Where the three providers actually diverge is whether that pool is
guaranteed:

| | AWS EKS | Azure AKS | GCP GKE |
|---|---|---|---|
| System pool creation | Facet default only (`cluster/aws-eks/variables.tf:178` defaults `var.pools` to `{}`) | Module-level, unconditional (`cluster/azure-aks/main.tf:340` inline `default_node_pool`) | Module-level, unconditional (`cluster/gcp-gke/main.tf:129` dedicated `google_container_node_pool.system`) |
| Survives a user-supplied `cluster.pools` | **No** — the facet default (`facets/platform-aws.yaml:117`) is replaced wholesale the moment `cluster.pools` is set | Yes — the inline pool is independent of `var.pools` | Yes — the dedicated resource is independent of `var.pools` |
| `windsorcli.dev/pool[-class]` labels on the system pool | Yes (`cluster/aws-eks/main.tf:350-356`) | **No** — `default_node_pool` sets no `node_labels` | Yes (`cluster/gcp-gke/main.tf:169-172`) |
| Native `mode: System` set on a user-declared `class: system` pool | N/A (no such field on EKS) | **No** — `azurerm_kubernetes_cluster_node_pool.pools` hardcodes `mode = "User"` (`cluster/azure-aks/main.tf:499`) | N/A (no such field on GKE) |

The AWS gap is concrete, not theoretical:
`contexts/_template/tests/platform-aws.test.yaml:466` runs a `cluster.pools`
config with only a `gpu` entry and asserts Terraform receives exactly
that, no `system` entry synthesized. A user who customizes AWS pools at
all can end up with zero `CriticalAddonsOnly`-tainted nodes, while the
identical customization on Azure or GCP cannot remove their inline
system pool. GCP's own module carries a comment claiming parity it
doesn't have: `cluster/gcp-gke/main.tf:126` describes its taint as
"matching the inline system pool on aws-eks/azure-aks" — aws-eks has no
inline system pool.

Separately, `schema.yaml:901` and `:944` document the auto-injected
label keys as `windsor.io/pool[-class]`; every provider actually emits
`windsorcli.dev/pool[-class]` (`cluster/aws-eks/main.tf:352`,
`cluster/gcp-gke/main.tf:171`). Code is consistent across providers; the
schema text is stale.

Finally, no provider schedules any Windsor-deployed component onto the
system pool it creates. Something does already land there on every
provider — each cloud's own vendor-managed system pods ship a
`CriticalAddonsOnly:Exists` toleration in their default manifests, a
convention old enough to predate all three clouds (EKS-managed
`coredns`, GKE's `kube-dns`, AKS's CoreDNS/metrics-server/konnectivity).
That's cloud-vendor behavior, not anything Windsor configured. AWS's own
guidance goes further and names the pattern Windsor doesn't yet follow:
["Addons deployed using Kubernetes resources, like Deployment, should
always tolerate the CriticalAddonsOnly taint and have nodeAffinity to be
deployed to system worker
nodes"](https://docs.aws.amazon.com/eks/latest/userguide/critical-workload.html).

Commit 43be8d88 gave a fixed list of platform-tier components (Flux
controllers, CoreDNS, external-dns, cert-manager, MetalLB, kube-vip,
Kyverno, Envoy Gateway, CloudNativePG, Crossplane, Prometheus, OpenEBS,
Keycloak Operator) a shared `priorityClassName:
windsorcli-platform-critical`, which protects them from eviction under
node pressure but does not place them anywhere — none of them carries a
toleration for `CriticalAddonsOnly`, so the taint excludes every one of
them from the system pool outright; they land on general/user capacity
wherever the scheduler puts them, same as any other workload.

Static-node providers (Talos: metal, docker, incus, hyperv) have no
pool concept at all, by design — `schema.yaml:877-880` already scopes
`cluster.pools` to "elastic providers (aws, azure, gcp, omni)". This ADR
doesn't extend the concept there: a 1-3 node dev cluster loses more
capacity cordoning off a system node than it gains from isolation.

None of the three providers make the system pool highly available, and
`topology: ha` doesn't touch it. AWS's `system_node_pool.desired_size`,
Azure's `default_node_pool.node_count`, and GCP's
`system_node_pool.node_count` all default to a single fixed node with
autoscaling off. `topology == 'ha'` only widens which AZs a pool's nodes
may land in (`node_subnet_ids`, `availability_zones`, `node_locations`)
for pools that already have enough replicas to spread — a single node
can't be spread across AZs regardless of how many are eligible. This
bites concretely on AWS: the EKS-managed `coredns` addon ships a default
`topologySpreadConstraints` keyed on `topology.kubernetes.io/zone`
specifically to land its 2 replicas in different AZs when capacity
allows, but a single-node system pool forces both CoreDNS replicas and
both CSI controllers onto that one node regardless of topology, making
DNS resolution and volume provisioning a single point of failure in an
`ha` cluster. All three modules already carry a `max_size`/`max_count`
of 3 on the system pool, currently dead code since autoscaling is off by
default — a strong signal this was anticipated and never finished.

## Decision

### 1. AWS EKS gets a module-level system node group, independent of `var.pools`

Add a dedicated system-pool resource to `terraform/cluster/aws-eks`,
mirroring GCP's standalone `google_container_node_pool.system` rather
than sourcing the system pool from `var.pools`. `facets/platform-aws.yaml`
drops the `system` entry from its `cluster.pools` default, matching how
`platform-azure.yaml` and `platform-gcp.yaml` already default to
`general` only. A user's `cluster.pools` can no longer remove AWS's
system pool, same as Azure and GCP today.

### 2. Azure gets the labels and native `mode` it's missing

`default_node_pool` gets a `node_labels` block setting
`windsorcli.dev/pool=<name>` / `windsorcli.dev/pool-class=system`, matching
AWS and GCP. `azurerm_kubernetes_cluster_node_pool.pools` sets
`mode = each.value.class == "system" ? "System" : "User"` instead of the
hardcoded `"User"`, so a user-declared additional `class: system` pool on
Azure gets AKS's own native system-pool semantics, not just the taint.

### 3. Fix the `schema.yaml` label documentation

Change `windsor.io/pool[-class]` to `windsorcli.dev/pool[-class]` at
`schema.yaml:901` and `:944`. Text-only; no behavior change.

### 4. Tolerate and prefer the system pool for the existing platform-critical list

Reuse the exact component list from commit 43be8d88 — no new list. This
follows AWS's own documented pattern for critical Deployments (toleration
plus nodeAffinity toward system capacity), extended to all three
providers rather than AWS alone. In each component's `helm-release.yaml`
values, alongside the existing `priorityClassName`:

- Deployments get a toleration for `CriticalAddonsOnly=true:NoSchedule`
  plus a `preferredDuringSchedulingIgnoredDuringExecution` node affinity
  toward `windsorcli.dev/pool-class: system`. Soft, not required — these
  still schedule normally where no system pool exists.
- DaemonSets (MetalLB speaker, kube-vip) get the toleration only. A
  DaemonSet already runs on every eligible node; a scheduling preference
  has no effect on it.

### 5. `topology: ha` makes the system pool 3 fixed nodes, one per AZ

Deferred — scoped here, not yet implemented.

Wire the system pool's node count to `topology` at the facet layer, the
same place `availability_zones`/`node_locations`/`node_subnet_ids`
already branch on `topology == 'ha'` today: `system_node_pool.desired_size`
(AWS), `default_node_pool.node_count` (Azure), and
`system_node_pool.node_count` (GCP) become 3 under `ha`, 1 otherwise. The
Terraform modules keep their single-node default unchanged for bare
callers; the facet supplies the topology-aware override, matching how
every other topology-driven knob in these facets is layered. Three nodes
matches the AZ count these same facets already use for `ha` (AWS/GCP
spread across all available zones, Azure across zones `1`-`3`), giving
CoreDNS's own AZ-spread `topologySpreadConstraints` real capacity to use
instead of collapsing onto a single node.

## Consequences

- Every AWS EKS cluster now provisions at least two node groups (system
  + general) at minimum, same baseline Azure and GCP already carry. AWS
  clusters that today rely on a single implicit pool see a real
  infrastructure change and a small cost increase on next apply.
- Azure's `mode = "System"` change only affects a `cluster.pools` entry
  explicitly declared `class: system` in addition to the default pool;
  no existing config without one is affected.
- The toleration/affinity addition is additive and safe on every
  provider and topology, including Talos, where the label/taint simply
  never matches and the preference is a no-op.
- Platform-tier components gain an actual placement preference to match
  the eviction protection they already have, closing the gap where
  43be8d88's "shielding" protected components that weren't reliably
  landing on protected capacity in the first place.
- Once decision 5 lands, an `ha` cluster pays for 3 small system nodes
  instead of 1 on every provider, in exchange for CoreDNS and the CSI
  controllers surviving a single node loss — the same cost/redundancy
  trade `topology: ha` already makes elsewhere in these facets.

## Alternatives considered

**Leave AWS's system pool as a facet default.** Rejected — it's silently
droppable by any user who sets `cluster.pools`, which is the opposite of
parity with Azure and GCP.

**Invent a new pool class name instead of reusing "system."** Rejected —
`system` is AKS's own native term and matches the taint convention AWS's
and GCP's own best-practice docs already recommend; a new name would add
vocabulary without adding clarity.

**Hard-require platform-tier pods onto the system pool via
`nodeSelector` instead of a soft affinity.** Rejected — breaks any AWS
cluster with no system pool declared and breaks Talos entirely, where no
system pool exists at all.

**Make the system pool autoscale instead of a fixed 3 nodes under
`ha`.** Rejected for decision 5 — CoreDNS and the CSI controllers need
fixed redundancy across AZs, not elastic capacity that can scale to 1
under low load and reintroduce the single-node problem this decision
exists to close.

## References

- [Use System Node Pools in AKS](https://learn.microsoft.com/en-us/azure/aks/use-system-pools) — AKS's native `mode: System`/`CriticalAddonsOnly` primitive.
- [Amazon EKS Best Practices Guide — Reliability](https://docs.aws.amazon.com/eks/latest/best-practices/reliability.html) — dedicated node group for critical add-ons as a documented pattern, not an API primitive.
- [Isolate workloads in dedicated node pools (GKE)](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/isolate-workloads-dedicated-nodes) — taint/affinity as the GKE-recommended mechanism, no native "system" mode.
- [Manage system critical workloads (EKS)](https://docs.aws.amazon.com/eks/latest/userguide/critical-workload.html) — AWS's own recommendation that critical Deployments carry both the `CriticalAddonsOnly` toleration and a system-pool nodeAffinity, the pattern decision 4 extends to all three providers.
- `terraform/cluster/aws-eks/variables.tf:178`, `terraform/cluster/azure-aks/main.tf:340`, `terraform/cluster/gcp-gke/main.tf:129` — current per-provider system pool creation.
- `contexts/_template/tests/platform-aws.test.yaml:466` — the test demonstrating AWS's system pool can be dropped entirely.
- `schema.yaml:877-880` — the existing elastic-vs-static-node provider scope for `cluster.pools`.
- [Recent changes to the CoreDNS add-on](https://aws.amazon.com/blogs/containers/recent-changes-to-the-coredns-add-on/) — the default `topologySpreadConstraints` decision 5 gives real capacity to use.
