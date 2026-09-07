---
title: "ADR-0012: System node pool parity across AWS, Azure, and GCP"
description: "Azure and GCP always provision a tainted system node pool independent of user pool config; AWS's only exists as a facet default that a user's own cluster.pools silently drops. No provider schedules platform-tier controllers onto the system pool it creates, and none makes it highly available under topology: ha. Closes these gaps by making AWS's system pool module-level like GCP's, tolerating/preferring only the control-glue half of the platform-critical list onto system capacity, and wiring topology: ha to a 2-node system pool with raised replicas on the components individually confirmed to support it safely."
---

# ADR-0012: System node pool parity across AWS, Azure, and GCP

## Status

Proposed. Decisions 1 and 3 merged in
[PR #2719](https://github.com/windsorcli/core/pull/2719); decision 2 merged
in [PR #2721](https://github.com/windsorcli/core/pull/2721); decision 4
merged in [PR #2724](https://github.com/windsorcli/core/pull/2724).
Decisions 5 and 6 are implemented, in review.

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

That list conflates two different bars, though. "Survives eviction
under pressure" is a loose criterion the whole list reasonably meets.
"Belongs physically on a small, isolated system pool" is a much
narrower one, and every CSP's own convention draws it the same way:
AKS's docs describe the system pool's job as hosting pods "like CoreDNS
and metrics-server" specifically, and AWS's/GKE's guidance points at
the same shape — DNS, CNI, CSI *controllers*, admission webhooks. None
of the native examples are throughput- or storage-heavy. Prometheus
(TSDB memory/storage scales with cardinality and retention), OpenEBS's
`dynamic-localpv` and Mayastor (storage data planes — Mayastor's
`io-engine` in particular is resource-intensive and often has node/disk
locality needs a generic burstable system node can't satisfy), and the
Envoy Gateway *proxy* (`envoy-proxy.yaml`, the actual traffic data
plane, not the `gateway-helm` control-plane chart) don't fit that
shape. Pinning them toward system capacity either starves them against
an intentionally small pool or forces the pool to grow to
general-purpose scale, which defeats the isolation this ADR exists to
get right — and contradicts the "system pool stays small" comment
already written into the Azure and GCP modules. Crossplane's
reconciliation load is bursty enough to be a similar poor fit.

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

### 4. Tolerate and prefer the system pool for the control-glue subset of the platform-critical list

Split the 43be8d88 list by the same control-glue-vs-workload line every
CSP already draws natively. Only the control-glue half gets a
toleration and a placement preference; the rest keeps its
`priorityClassName` unchanged and is untouched by this decision:

- **Prefer system capacity** (toleration + affinity): Flux controllers,
  CoreDNS (`addon-private-dns`), external-dns, cert-manager, Kyverno,
  MetalLB, kube-vip, Keycloak Operator, the CloudNativePG *operator*
  (`kustomize/database/install/cloudnativepg/helm-release.yaml` — the
  controller only; CNPG `Cluster` instances it manages are a separate
  resource tier, untouched), and Envoy Gateway's *control plane*
  (`kustomize/gateway/install/envoy/helm-release.yaml` — the
  `gateway-helm` chart's own controller, not the proxies it programs).
- **Unchanged** — priority class only, no toleration, no affinity:
  Prometheus, OpenEBS (`dynamic-localpv`, Mayastor), Crossplane, and
  Envoy Gateway's *proxy* (`envoy-proxy.yaml`'s `envoyDeployment`
  patch — the traffic data plane).

For the components that do get it, alongside the existing
`priorityClassName` in each `helm-release.yaml`/`kustomization.yaml`:

- Deployments get a toleration for `CriticalAddonsOnly=true:NoSchedule`
  plus a `preferredDuringSchedulingIgnoredDuringExecution` node affinity
  toward `windsorcli.dev/pool-class: system`. Soft, not required — these
  still schedule normally where no system pool exists.
- DaemonSets (MetalLB speaker, kube-vip) get the toleration only. A
  DaemonSet already runs on every eligible node; a scheduling preference
  has no effect on it.

Flux's own controllers are Terraform-managed
(`terraform/gitops/flux/main.tf`), not Helm charts under `kustomize/` —
the same toleration/affinity intent applies, but the mechanism has to
match whatever `terraform/gitops/flux` already uses to set their
`priorityClassName`, not the Helm-values pattern above.

### 4a. Re-check system pool sizing once decision 4 lands

Even the narrowed control-glue set is real aggregate load — four Flux
controllers, two CoreDNS replicas, external-dns, cert-manager's three
pods, Kyverno, MetalLB, kube-vip, Keycloak Operator, the CNPG operator,
and Envoy Gateway's control plane, layered on top of the vendor-managed
pods (cloud CoreDNS/kube-dns, CSI controllers, CNI/kube-proxy
DaemonSets) already landing there per the Context section above. That's
more than any single CSP's own system pool natively hosts. Validate
against real resource requests once decision 4 is deployed rather than
guessing a number now; the likely outcome is a modest size bump (one
instance-type tier, e.g. `.xlarge` in place of `.large`) on top of
whatever decision 5 does for node count, not a fundamental
rearchitecture.

### 5. `topology: ha` makes the system pool 2 fixed nodes

Wire the system pool's node count to `topology` at the facet layer, the
same place `availability_zones`/`node_locations`/`node_subnet_ids`
already branch on `topology == 'ha'` today: `system_node_pool.desired_size`
(AWS), `default_node_pool.node_count` (Azure), and
`system_node_pool.node_count` (GCP) become 2 under `ha`, 1 otherwise. The
Terraform modules keep their single-node default unchanged for bare
callers; the facet supplies the topology-aware override, matching how
every other topology-driven knob in these facets is layered.

Two, not three: nothing on the system pool needs majority quorum the way
etcd/control-plane does. Every component decision 4 places there uses
Kubernetes lease-based leader election (a standby, not a quorum) —
losing one of two nodes still leaves a live leader. Three nodes only
buys tolerance for two simultaneous node failures, which is
disproportionate for a tier whose entire premise is staying small, and
it would be the one place this ADR hardcodes a node count instead of
following the pattern every other pool in these facets already uses:
`topology: ha` widens *zone eligibility*, it doesn't force a specific
count. Two nodes still gives CoreDNS's own AZ-spread
`topologySpreadConstraints` real capacity to use instead of collapsing
onto a single node.

**2 total nodes only helps if they land in different zones**, so this
was checked per provider rather than assumed. AWS's `desired_size` and
Azure's `node_count` are both already totals — each cloud's own
infrastructure layer (EC2 Auto Scaling's default launch behavior for
AWS, AKS's own "best-effort zone balancing" for Azure) spreads a fixed
count across the eligible AZs/zones without any extra configuration
from this module. GCP is the exception: `google_container_node_pool`'s
`node_count` is **per zone**, not total — under `topology: ha`,
`node_locations` spans every available zone (often 3), so a plain
`node_count = 2` would silently create 6 nodes, not 2. The fix uses
`autoscaling.total_min_node_count`/`total_max_node_count` (mutually
exclusive with plain `node_count`) instead, with `location_policy =
"BALANCED"` — this keeps the total fixed at 2 while leaving every zone
in `node_locations` schedulable, so GKE can still place (or later
rebalance) into whichever zone actually has capacity, rather than
hard-restricting eligibility to a fixed 2-zone subset.

### 6. `topology: ha` raises replicas on the components verified to support it safely

Decision 5 alone doesn't deliver zero-downtime HA. Verified live against
a running single-node cluster: cert-manager, its webhook and cainjector,
CoreDNS, external-dns, the CloudNativePG operator, and both Kyverno
controllers (admission and background) all run at a single replica
today. A 2-node system pool with every controller still at one replica
gives self-healing (Kubernetes reschedules the lone pod onto the
surviving node) but not zero downtime — there's a restart gap. Raising
replicas closes that gap, but only for components confirmed — against
their own project's documentation or source, not assumed from "it's an
operator/controller so it probably has leader election" — to support
running more than one safely:

- **Bump to 2 replicas under `ha`**: Flux's four default controllers
  (all support `--enable-leader-election`, already wired via this
  module's `leader_election` variable), cert-manager plus its webhook
  and cainjector (leader election on by default), the CloudNativePG
  operator (leader election built in; `replicaCount: 2` is CNPG's own
  documented HA pattern), Kyverno's `backgroundController` (requires
  leader election to serialize generate/mutate-existing reconciliation,
  so a standby is exactly what 2 buys), and CoreDNS (fully stateless,
  needs no leader election at all to run N replicas safely).
- **Bump to 3 replicas under `ha`**: Kyverno's `admissionController`
  specifically. Unlike `backgroundController`, it doesn't use leader
  election for handling requests — replicas actively load-balance
  incoming AdmissionReviews rather than one standing by — and Kyverno's
  own docs state 3 as the minimum for a genuinely highly-available
  admission controller. 2 wouldn't be wrong, exactly, but it undersells
  what this component actually needs; 3 still fits comfortably on a
  2-node system pool, it just means one node runs two of its pods.
- **Leave at 1, pending verification**: external-dns, the MetalLB
  controller, and Keycloak Operator. External-dns lacks reliable
  built-in leader election at the pinned version — running 2 replicas
  risks racy or duplicate DNS provider API writes. The MetalLB
  controller has none at all: the chart's Deployment template has no
  `replicas` field, and the MetalLB project explicitly advises against
  scaling it past 1 — multiple controllers can race to update the same
  LoadBalancer Service. Keycloak Operator's framework (the Java
  Operator SDK) *supports* leader election, but only when explicitly
  enabled, and the vendored manifest here doesn't enable it — assuming
  the capability exists is not the same as confirming it's on. For all
  three, doubling replicas without confirmed leader election is a
  reliability regression dressed up as an HA improvement, not one.
- MetalLB's speaker and kube-vip are DaemonSets, already running on
  every eligible node regardless of topology; replica count doesn't
  apply to them.

The mechanism turned out to already exist: this codebase has an
established `<component>/ha` kustomize-component convention (a
`topology == 'ha'`-gated component per install, e.g. `coredns/ha`,
`cloudnativepg/ha`), so decision 6 extends that pattern rather than
introducing a parallel one. Flux is the one exception — it's
Terraform-managed, not kustomize, so it gets an explicit `var.replicas`
(number, not a `var.ha` boolean — Terraform inputs should say what they
configure, not encode a topology decision implicitly) instead.

Auditing the existing `<component>/ha` components against this decision
surfaced three corrections, made alongside it rather than deferred:

- **`coredns/ha` set `replicaCount: 3`**, which doesn't fit a 2-node
  system pool cleanly (2 replicas share one node). CoreDNS needs no
  leader election and no vendor-mandated minimum, so it's reduced to 2
  — a clean one-per-node spread, consistent with the "2 is enough, no
  quorum needed" reasoning behind decision 5's own node count.
- **`kyverno/ha` didn't touch `backgroundController`**, only
  `admissionController`. Since `backgroundController` genuinely needs
  leader election (serializing generate/mutate-existing
  reconciliation), it now gets the standard 2-replica-plus-PDB
  treatment alongside `admissionController`'s pre-existing 3.
- **`external-dns/ha` was broken.** It set `extraArgs:
  [--enable-leader-election]`, but that flag doesn't exist in the
  pinned external-dns version — confirmed by searching the entire
  v0.22.0 source tree, not just its documented flags, which returned
  zero references to leader election outside a proposal doc. Any
  cluster that has actually run `topology: ha` with the private-dns
  addon enabled has likely had a crash-looping external-dns pod. Fixed
  by removing the component and its wiring entirely — running
  external-dns at 2 replicas without real leader election is a
  regression (racy/duplicate provider writes), not a fix, so there is
  currently no safe `ha` treatment for it to fall back to.

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
- Only the control-glue half of the platform-tier list gains an actual
  placement preference, closing the gap where 43be8d88's "shielding"
  protected components that weren't reliably landing on protected
  capacity — without also concentrating Prometheus/OpenEBS/Crossplane/
  the Envoy proxy onto capacity sized for CoreDNS-shaped workloads.
- System pool sizing needs re-validating once decision 4 ships (4a) —
  treat the current instance-type defaults as provisional until real
  usage is measured, not as a settled number.
- Once decision 5 lands, an `ha` cluster pays for 2 small system nodes
  instead of 1 on every provider, in exchange for CoreDNS and the CSI
  controllers surviving a single node loss — the same cost/redundancy
  trade `topology: ha` already makes elsewhere in these facets, sized to
  what leader-election-based redundancy actually needs rather than a
  quorum count borrowed from etcd/control-plane thinking.
- Decision 6 only closes the zero-downtime gap for components verified
  to support it safely; external-dns, the MetalLB controller, and
  Keycloak Operator stay at 1 replica, so decision 5 alone (self-healing,
  not zero-downtime) is what they get in the meantime. Kyverno's
  `admissionController` gets 3 rather than 2, matching its own
  documented HA minimum rather than the standby-replica count that
  fits everything else.
- CoreDNS's private-zone data still comes from a single-member etcd
  `StatefulSet` (`coredns/etcd`), untouched by `topology: ha` and
  unrelated to CoreDNS's own replica count. Not a hard outage — the
  `etcd` plugin falls through to public forwarders on failure — but
  private-domain resolution breaks until that one pod recovers. Real
  etcd HA needs an odd member count (3, not 2) with per-member peer
  TLS and `--initial-cluster` wiring, a separate piece of work from
  this ADR.

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

**Reuse the full 43be8d88 list unmodified for decision 4, including
Prometheus/OpenEBS/Crossplane/Envoy Gateway's proxy.** Rejected — that
list was scoped for eviction priority, a looser bar than physical
placement on a small isolated pool. Every CSP's own system-pool
convention is control-glue only (DNS, CNI, CSI controllers, admission
webhooks); forcing storage/metrics/data-plane workloads onto the same
capacity either starves them or forces the "system" pool to grow to
general-purpose scale, defeating the isolation this ADR is built
around.

**Make the system pool autoscale instead of a fixed node count under
`ha`.** Rejected for decision 5 — CoreDNS and the CSI controllers need
fixed redundancy, not elastic capacity that can scale to 1 under low
load and reintroduce the single-node problem this decision exists to
close.

**Use 3 system nodes instead of 2 for decision 5.** Rejected — nothing
on the system pool needs etcd/control-plane-style majority quorum.
Every component decision 4 places there uses lease-based leader
election, where 2 is enough to have a standby; 3 only buys tolerance
for two simultaneous node failures, disproportionate for a tier whose
whole premise is staying small. It would also be the one place this ADR
hardcodes a node count instead of following the pattern every other
pool in these facets uses — widening zone eligibility under `ha`
without forcing a specific count.

**Bump every component in decision 4's list uniformly to 2 replicas for
decision 6.** Rejected — assuming leader election from "it's an
operator/controller" is exactly the mistake this decision is built to
avoid. External-dns lacks confirmed leader election at the pinned
version; the MetalLB controller has none and the project explicitly
advises against scaling it; Keycloak Operator's framework supports it
but the vendored manifest doesn't confirm it's enabled. Running 2
replicas on any of these is a reliability regression dressed up as an
HA improvement. Kyverno's `admissionController` cuts the other way — a
uniform "2 for everything" would undersell it, since Kyverno's own docs
call for 3 as the minimum for genuine HA there.

## References

- [Use System Node Pools in AKS](https://learn.microsoft.com/en-us/azure/aks/use-system-pools) — AKS's native `mode: System`/`CriticalAddonsOnly` primitive.
- [Amazon EKS Best Practices Guide — Reliability](https://docs.aws.amazon.com/eks/latest/best-practices/reliability.html) — dedicated node group for critical add-ons as a documented pattern, not an API primitive.
- [Isolate workloads in dedicated node pools (GKE)](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/isolate-workloads-dedicated-nodes) — taint/affinity as the GKE-recommended mechanism, no native "system" mode.
- [Manage system critical workloads (EKS)](https://docs.aws.amazon.com/eks/latest/userguide/critical-workload.html) — AWS's own recommendation that critical Deployments carry both the `CriticalAddonsOnly` toleration and a system-pool nodeAffinity, the pattern decision 4 extends to all three providers.
- `terraform/cluster/aws-eks/variables.tf:178`, `terraform/cluster/azure-aks/main.tf:340`, `terraform/cluster/gcp-gke/main.tf:129` — current per-provider system pool creation.
- `contexts/_template/tests/platform-aws.test.yaml:466` — the test demonstrating AWS's system pool can be dropped entirely.
- `schema.yaml:877-880` — the existing elastic-vs-static-node provider scope for `cluster.pools`.
- [Recent changes to the CoreDNS add-on](https://aws.amazon.com/blogs/containers/recent-changes-to-the-coredns-add-on/) — the default `topologySpreadConstraints` decision 5 gives real capacity to use.
- [Kyverno High Availability](https://kyverno.io/docs/guides/high-availability/) — `admissionController` uses no leader election and needs 3 replicas minimum for real HA; `backgroundController` does use leader election, where 2 is enough.
- [MetalLB controller leader election tracking issue](https://github.com/metallb/metallb/issues/2226) — confirms the controller has none today and the project advises against scaling it past 1 replica.
- [CloudNativePG Installation and upgrades](https://cloudnative-pg.io/documentation/1.27/installation_upgrade/) — `replicaCount: 2` as CNPG's own documented operator HA pattern, leader election built in.
- [`google_container_node_pool` (Terraform Registry)](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_node_pool) — `node_count` is per zone; `total_min_node_count`/`total_max_node_count` and `location_policy` are the total-across-zones alternative decision 5 uses for GCP.
