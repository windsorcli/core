---
title: "ADR-0025: Proxmox VMs can be placed on several nodes of one cluster"
description: Add proxmox.nodes so one context places Talos VMs round-robin on the nodes of one Proxmox cluster, with one image download per node and no state move for single-node contexts.
---

# ADR-0025: Proxmox VMs can be placed on several nodes of one cluster

## Status

Proposed (2026-11-07). Builds on [ADR-0023](0023-node-addresses-from-dhcp-or-explicit.md),
which fixed how Proxmox nodes get an address. ADR-0024 (core#3345, the
host-level Proxmox component) is a separate record. Section 8 states how the
two fit together. Scope is `platform: proxmox` with `cluster.driver: talos`.

## Context

`terraform/compute/proxmox` takes one `node_name`. It uses that value in three
places:

- `data "proxmox_datastores" "node"` reads the datastores of the node.
- `proxmox_download_file.images` downloads each image to the node.
- `proxmox_virtual_environment_vm.instances` creates each VM on the node.

The facet requires `proxmox.node`. A user with three Proxmox nodes and three
control planes gets three VMs on one node. If that node fails, the Kubernetes
API fails with it.

These facts decide the design:

- In `bpg/proxmox` 0.116.0 and 0.120.0, `node_name` is a required argument of
  `proxmox_download_file`, `proxmox_virtual_environment_vm`, and the data source
  `proxmox_datastores`. One resource instance therefore acts on one node.
- Each VM disk sets `import_from` to the file id of the image, which has the
  form `<datastore>:import/<file>`. The id holds no node name. When the image
  datastore is local storage, each node has its own copy of the storage, so the
  same id names a different file on each node.
- Pools, users, and VM IDs belong to the whole Proxmox cluster (or to the host,
  when it is standalone). The `vm_id`
  check in the module already sees VMs on every node.
- The data source `proxmox_virtual_environment_nodes` has no required argument.
  In both provider versions it returns parallel lists: `names` and `online`,
  plus `cpu_count`, `memory_available`, `memory_used`, `cpu_utilization`,
  `uptime`, `ssl_fingerprints`, and `support_levels`.

## Decision

### 1. Goal and scope

One context MUST be able to create Talos VMs on several nodes of one Proxmox
cluster. A context with three control planes and three nodes places one control
plane on each node.

One context targets one Proxmox endpoint. That endpoint is either:

- A cluster. The nodes in `proxmox.nodes` are nodes of that cluster.
- A standalone host that is not in a cluster. This is the single-node case
  that works today, with `proxmox.nodes` of length one.

The operator does not select a mode. The values are the same for both, and the
module does not check whether the endpoint is a cluster. A standalone host
has one node, so the round-robin rule puts every VM on it.

These are out of scope:

- Several standalone hosts in one context. Each host is a separate endpoint,
  and the provider authenticates to one endpoint.
- Several Proxmox clusters in one context, for the same reason.
- Installing Proxmox and forming a cluster. The provider has no resource for
  either.

### 2. The `proxmox.nodes` value

`proxmox.nodes` is a list of node names:

```yaml
proxmox:
  nodes: [pve1, pve2, pve3]
```

`proxmox.node` is removed. A single-node context sets `nodes: [pve]`. The platform
is pre-release, so the rename needs no alias. A `requires` rule on `proxmox.nodes`
fails composition when the list is missing or empty. A name MAY appear more than
once; see section 3.

The first entry is the primary node. The facet passes it to the module as
`node_name` and sets both values in `proxmox_effective`.

### 3. Placement

The default is round-robin. Control plane N and worker N each take
`nodes[(N - 1) % len(nodes)]`. Control planes and workers count separately, so
`controlplane-1` and `worker-1` both land on the first node. The result is
stable: a change to `count` does not move an existing VM, because the position
of a VM in its pool does not change.

The placement ignores node resources. The operator has three ways to handle
nodes of unequal size:

- Order the list. The first entries fill first when counts are small.
- Repeat a name. With `nodes: [big, big, small]`, `big` gets two of every three
  VMs. The checks and downloads in sections 4 and 6 run once for each distinct
  node.
- Override the node of one VM, as described next.

The module does not read node CPU or memory. Those values change between plans,
and a placement that follows them would move VMs.

An operator MAY override the node of one VM with the field `placement` in
`cluster.controlplanes.nodes.controlplane-N` and `cluster.workers.nodes.worker-N`:

```yaml
cluster:
  workers:
    nodes:
      worker-1: { node: 192.168.3.51, endpoint: 192.168.3.51:50000, placement: pve2 }
```

The value MUST be in `proxmox.nodes`. A VM without the field follows the
round-robin rule, and an override does not shift the position of other VMs. The
name `placement` is not specific to Proxmox, so the shared node schema holds no
vendor name; the schema description says what it means on Proxmox. The name
`node` is not available, because `node` already holds the guest address. The
shared schema requires `endpoint` and `node` on each entry, so a DHCP context
that places a VM writes both fields too.

This ADR does not define what happens when an operator changes the node of an
existing VM. The real-cluster test records what the plan shows.

The module gets an optional `node_name` on each item in `instances`. An
instance without it uses `var.node_name`, so existing callers do not change. The
module gets a `nodes` variable (list of string, default null) for the node
list, and `node_name` stays required.

### 4. Images

An image MUST exist on the node that boots from it. The module downloads in one
of two modes:

- On local storage (the default), the module downloads each image once on each
  node that gets a VM.
- With `proxmox.image_datastore_shared: true`, the module downloads each image
  once. The storage is shared, so every node sees the file. The module sets
  `image_datastore_shared` (bool, default false) for this. The operator states
  that the storage is shared; the module does not detect it.

The disk keeps `import_from` as the file id string. Each VM depends on the
download for its own node, so Terraform creates the download before the VM and
destroys it after the VM.

### 5. Resource addresses do not change

A single-node context MUST show no plan change after the upgrade, and MUST NOT
need a state move. The module keeps two existing resources on the primary node
(`var.node_name`, the first entry of the list):

- `proxmox_download_file.images`, keyed by image, as today.
- `data.proxmox_datastores.node`, as today.

Other nodes get new resources:

- `proxmox_download_file.extra_images`, keyed by `<image>/<node>`, for each
  node other than the primary node. It does not exist with
  `image_datastore_shared: true`.
- `data.proxmox_datastores.extra`, keyed by node.

A `moved` block cannot take a node name that is unknown at authoring time, so
new resources avoid a state move. The VM resource `instances` keeps its
address and key. Only its `node_name` argument changes, and for a single-node
context it does not change.

### 6. Plan-time checks

Each check fails at plan time with one message that names the node and the
object. The checks run for every node that gets a VM or an image:

- The node is in the cluster and is online. The check reads
  `proxmox_virtual_environment_nodes` (`names` and `online`).
- The VM datastore (`datastore_id`) exists on every node that gets a VM.
- The image datastore (`image_datastore_id`) exists on every node that gets an
  image, and its `content_types` include `import`.

These checks extend the checks that the module has today for one node. They
need the same privileges as before (`Datastore.Audit`) on each node.

A pool with fewer nodes than control planes is allowed. Two control planes then
share a node, and the README says so. The module does not fail on it, because a
single-node context already puts all control planes on one node.

### 7. What does not change

- `cluster/talos` and the `gitops` component do not change.
- The outputs `controlplanes` and `workers` keep their fields.
- One resource pool serves all nodes, and `proxmox.pool` keeps its meaning.
- VM IDs stay cluster-wide. `proxmox.vm_id_start` keeps its formulas, and a VM
  gets the same ID on any node.
- The Talos VIP (`cluster.vip`) needs all control planes on one layer-2
  bridge. Every node in `proxmox.nodes` MUST have the bridge named in
  `proxmox.bridge`, with the same VLAN and the same layer-2 reach. The module
  checks neither.

### 8. Relation to the host-level component

ADR-0024 adds a host-level Proxmox component whose first object is a directory
storage. That storage takes a `nodes` argument, a list of nodes where the
storage is available. With this ADR, the facet passes the full
`proxmox_effective.nodes` list to it, so the storage exists on every node that
gets an image. The component keeps its own state and keeps `destroy: false`.

The provider documents `create_base_path` as "Create the base directory if it
doesn't exist." The documentation does not say whether it applies on every node
of `nodes`. The real-cluster test answers that (see Open questions).

### 9. Privileges

The Windsor user needs on every node in `proxmox.nodes` the same privileges that
it has today on one node: `Datastore.Audit` and `Datastore.AllocateSpace` on the
VM datastore, and the image datastore privileges in the module README. The node
check is likely to need `Sys.Audit`, which the README privilege list will name.
The real-cluster test confirms the exact privilege and path that the node data
source needs.

The facet adds no user, role, or ACL. They stay prerequisites.

## Consequences

- A Proxmox cluster with three nodes can host a three-control-plane cluster
  with one control plane per node. Losing one node leaves the Kubernetes API up,
  because etcd keeps two of three members.
- A single-node context upgrades with no plan change and no state move.
- Local storage costs one download per image and node. Shared storage costs
  one.
- Fewer nodes than control planes puts two control planes on one node. Losing
  that node can cost etcd quorum.
- A Proxmox cluster with two nodes loses its own quorum when one node fails,
  unless the operator adds a third vote: a third node, or a QDevice (an external
  corosync vote that hosts no VMs). Proxmox then blocks changes on the
  surviving node. This ADR does not fix that, and a two-node cluster is a
  supported but weak layout.
- `proxmox.nodes` replaces `proxmox.node`, and the schema gains `nodes` and
  `image_datastore_shared`.
- A node name is a name in the Proxmox cluster. A renamed node breaks the
  placement of its VMs.

## Open questions for the real-cluster test

The test runs on a Proxmox cluster with two or three nodes, and on a standalone
host. It MUST answer these questions before the work is done:

1. Does `proxmox_storage_directory` with `create_base_path = true` create the
   base directory on every node in `nodes`, or only on one?
2. Does the facet expression language support the `%` operator? If it does not,
   the facet needs another way to compute the index.
3. What is the exact schema of the data source
   `proxmox_virtual_environment_nodes` against a live cluster? The provider
   schema gives `names` and `online` as parallel lists. The test confirms that
   the order matches, and which privilege the data source needs.
4. Does `proxmox_virtual_environment_nodes` on a standalone host return that
   one host, with `online` true? If it does not, the node check needs a
   different rule for a one-entry list.
5. Does a plan on a single-node context show no change after the upgrade?
6. Does `destroy` remove the VMs and the downloads on every node?
7. Does the Kubernetes API stay up when one node stops?

## Alternatives considered

A map in the `proxmox` block (`proxmox.placement: {worker-1: pve2}`) keeps the
override away from the node entry and avoids the `endpoint` and `node` fields
under DHCP. It separates the setting from the node it describes, so the node entry
is the place for it.

A field named after the vendor (`proxmox_node`) puts a vendor name in the shared
schema. A field such as `host` or `zone` has a different meaning on each platform
(an availability zone on a cloud, a host on vSphere, a cluster member on Incus).

Moving `proxmox_download_file.images` to a `for_each` keyed by `<image>/<node>`
makes the code simpler. It also changes the address of every existing download,
so every single-node context shows a destroy and create in its plan. A `moved`
block cannot map to a key with a node name that the module does not know when
the author writes it.

Allowing one module call per node would keep each call single-node. It splits
the instance list, the checks, and the outputs across calls, and the facet then
has to merge the outputs of several calls. One call with a node on each
instance is smaller.

Detecting shared storage from the `shared` field of `proxmox_datastores` would
remove `image_datastore_shared`. The data source returns `shared` for each
datastore, but the module would have to read it before it can plan the
downloads, and a wrong value silently skips a download. An explicit value is
easier to reason about. A later change MAY replace the value with detection.
