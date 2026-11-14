---
title: "ADR-0026: Talos nodes of different sizes use cluster.pools"
description: Extend cluster.pools to vSphere, Hyper-V, and Proxmox so one Talos context creates worker nodes of different sizes and targets them with labels and taints, with no change to the node names or Terraform addresses of existing contexts.
---

# ADR-0026: Talos nodes of different sizes use cluster.pools

## Status

Proposed (2026-11-14). Builds on [ADR-0023](0023-node-addresses-from-dhcp-or-explicit.md),
which fixed how static-node platforms get node addresses, and on
[ADR-0025](0025-proxmox-multi-node-placement.md), which fixed Proxmox placement.
Scope is `platform: vsphere`, `hyperv`, and `proxmox` with `cluster.driver: talos`.
Section 7 states what happens on `incus`, `docker`, and `metal`.

## Context

A Talos cluster on a static-node platform has one worker group, `cluster.workers`.
All workers share `cpu`, `memory`, `root_disk_size`, `disks`, and `image`.
`cluster.workers.nodes` sets only `endpoint`, `hostname`, `node`, `mac_address`,
`placement`, and `image` for each node. Nothing sets a worker label or a taint.
A user who needs GPU nodes, storage nodes, and general nodes in one cluster
cannot do it.

The elastic platforms (`aws`, `azure`, `gcp`) and the future `omni` provider
already have `cluster.pools`. It is a map of named pools. Each pool has a
`class`, a `count`, `labels`, and `taints`. The facets add the labels
`windsorcli.dev/pool=<name>` and `windsorcli.dev/pool-class=<class>`.

These facts from `main` (5709569b) decide the design:

- The three compute modules already take a list of instances with a `cpu`,
  `memory`, and `root_disk_size` for each instance. The facets fill every
  worker with the same values.
- The key of each instance in `compute/vsphere`, `compute/hyperv`, and
  `compute/proxmox` is the instance name. The Terraform address of a VM is
  `<resource>.instances["<name>"]`. The name is also the VM name.
- The facets build the worker names from the position in the group. A group
  with one worker has the name `worker`. A group with `N > 1` workers has the
  names `worker-1` to `worker-N`. Hyper-V ignores `hostname` and uses the
  same names.
- Without DHCP, `cluster.workers.nodes` MUST have an entry `worker-1` to
  `worker-N` (`cluster_node_addresses` in `platform-base.yaml`).
- `terraform/cluster/talos` accepts `config_patches` for each worker. The
  `compute/vsphere` module accepts `per_node_config_patches`, a map keyed by
  node name, and bakes it into the VM guestinfo.
- No compute module for `vsphere`, `hyperv`, or `proxmox` creates a data
  disk. `cluster.workers.disks` only tells Talos how to partition a disk that
  the VM already has.
- `cluster.pools` is not read on the static platforms. The schema comment says
  they "continue to use cluster.workers".

## Decision

### 1. Use `cluster.pools` on the static Talos platforms

`vsphere`, `hyperv`, and `proxmox` MUST read `cluster.pools`. One pool is one
group of worker nodes with the same size, labels, and taints. This gives one
concept on every platform: a user who knows pools on AWS reads the same
fields on vSphere, and an `omni` machine set later maps to a pool.

Per-node overrides in `workers.nodes` are rejected. Labels do not give nodes
of different sizes. A per-node `cpu`, `memory`, and `taints` set would grow
into a second pool concept that has no `count` and no name.

### 2. Pool fields on a static platform

| Field | Meaning on a static platform |
|---|---|
| `class` | Required, as on the elastic platforms. The facet emits the label `windsorcli.dev/pool-class=<class>` and does nothing else with it. A class has no size catalog on a static platform. |
| `count` | The number of nodes in the pool. |
| `labels` | Kubernetes labels for the nodes, set in the Talos machine config as `machine.nodeLabels`. |
| `taints` | Kubernetes taints for the nodes, set as `machine.nodeTaints`. |
| `cpu`, `memory`, `root_disk_size` | New pool fields, with the same meaning as the fields of `cluster.workers`. An unset value takes the value of `cluster.workers`, then the platform default. |
| `nodes` | New. The static addresses of the pool. Section 5 defines it. |
| `image`, `disks`, `volumes` | New. Phase 2 (section 8). |

Every node also gets `windsorcli.dev/pool=<pool name>`. A user label with one
of the two `windsorcli.dev/pool*` keys MUST be rejected.

The fields `autoscaling`, `lifecycle`, and `instance_types` have no meaning on a
static platform. A context that sets them on `vsphere`, `hyperv`, or `proxmox`
MUST fail composition with a message that names the field.

### 3. The rule for `cluster.workers` when `pools` is set

`cluster.workers` and `cluster.pools` MUST work together on the static
platforms. `cluster.workers` stays the default pool. A pool in `cluster.pools`
adds nodes. It never replaces or renames the nodes of `cluster.workers`.

- `cluster.pools` absent: `cluster.workers` behaves as it does today. The
  rendered blueprint, the instance list, and the machine config of every node
  MUST NOT change.
- `cluster.pools` set: the nodes of `cluster.workers` stay as they are. Each
  pool adds its own nodes. `cluster.workers.count` MAY be 0 or unset.
- The nodes of `cluster.workers` get no `windsorcli.dev/pool` label. They carry
  no injected label or taint in either case, so adding a pool never changes
  the machine config of an existing node.
- Facet values that count workers (`cluster_nodes_effective.workers`,
  `topology`, the default of `cluster.controlplanes.schedulable`) MUST count
  `cluster.workers.count` plus the `count` of every pool.

This differs from the elastic platforms. There, `pools` takes precedence over
`workers`, because no `workers` group creates nodes. On a static platform, a
rule that replaced `workers` would rename or delete the nodes of every context
that adds a first pool.

### 4. Names, addresses, and Terraform keys

The node name is the key of the instance in the compute module. It is also
the Terraform address key, the VM name, and the Kubernetes node name.

| Group | Node name | Terraform address | Address entry (no DHCP) |
|---|---|---|---|
| `cluster.workers` | `worker`, or `worker-N` when `count > 1` (unchanged) | `instances["worker-N"]` (unchanged) | `cluster.workers.nodes.worker-N` (unchanged) |
| Pool `<p>` | `<p>-N`, with `N` from 1, never without the number | `instances["<p>-N"]` | `cluster.pools.<p>.nodes.<p>-N` |

Rules:

- A pool node name always has the number, even when `count` is 1. A pool that
  grows from 1 to 2 nodes therefore keeps its first node. The group
  `cluster.workers` keeps its old rule, because a change would replace the
  VMs of every existing context.
- A pool grows by adding `<p>-(N+1)`. A pool shrinks by removing the highest
  `N`. There is no gap in the numbers.
- The pool names `worker` and `controlplane` are reserved on the static
  platforms. A pool with one of these names MUST fail composition.
- Hyper-V names guests by position, so the VM is `<p>-N` plus `name_suffix`,
  the same pattern as `worker-N` today.
- The compute modules do not change their `instances` key. Each facet expands
  a pool into one instance with `count: 1` for each node, as it does for
  `cluster.workers`.
- Proxmox placement follows ADR-0025 inside each pool. Node `N` of a pool goes
  to `proxmox.nodes[(N - 1) % len]`, unless `placement` is set. The Proxmox
  `vm_id` of a pool node MUST NOT depend on any other pool. When
  `proxmox.vm_id_start` is set, each pool MUST set its own `vm_id_start`.

### 5. Static addresses without DHCP

Each pool has `nodes`, a map with the same format as `cluster.workers.nodes`.
Without DHCP, a pool `<p>` with `count: N` MUST have the entries `<p>-1` to
`<p>-N`. With DHCP, `nodes` is optional, and `mac_address` and `placement`
keep their meaning. A missing entry fails composition with a message that
names the pool, as `workers_missing` does for the workers. The check MUST use
the user's vocabulary: "give each node of pool gpu an address under
cluster.pools.gpu.nodes".

The Hyper-V NAT port forwards and `talos_node_targets` MUST include the pool
nodes.

### 6. Where labels and taints go

Each node gets a Talos config patch with `machine.nodeLabels` and
`machine.nodeTaints`.

- vSphere: the patch joins `per_node_config_patches`. The module bakes it into
  the guestinfo of the VM.
- Hyper-V and Proxmox: the patch joins `config_patches` of the node in
  `terraform/cluster/talos`.

The `cluster` step reads the node list from the compute output. The facet MUST
add the patch to each node by node name.

### 7. Order and scope for each platform

1. `vsphere` first. It has a large customer and the module needs no change.
2. `hyperv` second. The M6 milestone has no open issue, so the gate is clear.
3. `proxmox` third. The M9 milestone has no open issue. The `vm_id` rule in
   section 4 is its only new work.
4. `incus`, `docker`, and `metal` MUST reject `cluster.pools`. The message is
   "cluster.pools is not supported on platform <p>; use cluster.workers". They
   are community grade and MUST NOT block the release. A later ADR MAY add them.

### 8. Phases

Phase 1 delivers, in one PR for the schema and `config-talos.yaml` and one PR
for each platform: `class`, `count`, `labels`, `taints`, `cpu`, `memory`,
`root_disk_size`, `nodes`, and the rules in sections 3 to 5. The size fields
cost almost nothing, because every compute module already takes them for each
instance. Labels and taints alone would not lower the risk, because the
naming and address work is the same.

Phase 2 delivers `image`, `disks`, and `volumes` for each pool, after phase 1
merges. Phase 2 is part of M11. A GPU pool needs its own Talos schematic and
so its own image. A storage pool needs a data disk, and no compute module
creates one today. Phase 2 therefore adds an optional `data_disks` list for
each instance in `compute/vsphere`, `compute/hyperv`, and `compute/proxmox`.
The pool field `disks` then means that the module creates the disk and Talos
partitions it. The phase 2 PR for each platform MUST state what happens to
the disk when a node is removed. `compute/vsphere` sets `ignore_changes` on
`disk`, so the PR MUST also state how it treats a disk added to an existing VM.

## Upgrade stability

No existing context changes. The plan has three checks, and the first two MUST
pass before the first platform PR merges.

1. Golden test. Before any facet change, the first commit records the
   `instances`, `per_node_config_patches`, and cluster `workers` inputs for
   `vsphere`, `hyperv`, and `proxmox` fixtures with `workers.count` of 0, 1,
   and 3, with and without DHCP. Every later commit MUST keep them equal with
   `cluster.pools` absent.
2. Blueprint diff. For each fixture, `windsor show blueprint` output with
   `cluster.pools` absent MUST be byte-identical before and after the change.
3. Plan on upgrade. The v0.8.0 to v0.9.x upgrade test in the acceptance
   repository applies a context on `main` from before the change, then plans
   with the new code. The plan MUST show no changes. A second plan with one
   pool added MUST show only creates, and no update or replace on an existing
   key.

## Consequences

- A context can add GPU, storage, and general pools to a Talos cluster on the
  three large static platforms, with labels and taints.
- `cluster.pools` has fields that differ by platform. The schema allows them
  all, and `requires` rules reject the wrong ones. The guide MUST list them.
- The nodes of `cluster.workers` cannot get labels or taints. A user who wants
  them moves the nodes to a pool. This replaces the VMs, because the names
  change. The migration guide MUST say so.
- A user who needs a storage pool before phase 2 attaches the data disk by
  hand and sets `cluster.workers.disks`, as today.
- A pool with `count: 1` that grows keeps its first node. A `cluster.workers`
  group with one node does not, and keeps the old rule.

## Open questions

1. Does a label or taint change on a running vSphere node reach the node?
   `cluster/talos` skips the machine config apply when `compute` bakes the
   config, and Talos reads guestinfo at boot. The vSphere PR MUST test this on
   a real cluster. If it fails, the PR adds an apply path for the patch.
2. Is the group `cluster.workers` allowed to carry `labels` and `taints`? This
   ADR says no, to keep one concept.
3. Does `class` stay required on static platforms, where it only sets a label?
   This ADR says yes, so the schema does not change for the elastic platforms.

## Alternatives considered

- Per-node overrides in `workers.nodes`. Rejected in section 1.
- Pools replace `cluster.workers` when set, as on the elastic platforms.
  Rejected in section 3: the nodes of existing contexts change name.
- A size catalog behind `class` on static platforms. Rejected: a static
  platform has no instance types, so a catalog hides numbers the user must
  choose.
- Labels only, with no sizes. Rejected: labels do not make nodes of different
  sizes, and the user asked for both.
