---
title: "ADR-0024: Host-level Proxmox objects live in an opt-in component"
description: Add a host component for Proxmox objects that outlive a context, starting with the image datastore, and state which objects belong to a context, to the host, or to the administrator.
---

# ADR-0024: Host-level Proxmox objects live in an opt-in component

## Status

Proposed (2026-11-07). Builds on [ADR-0019](0019-explicit-endpoints-dhcp-and-tls-sources.md)
and [ADR-0023](0023-node-addresses-from-dhcp-or-explicit.md). [ADR-0025](0025-proxmox-multi-node-placement.md)
extends the `nodes` input of this component to a list of several nodes.
Scope is `platform: proxmox` with `cluster.driver: talos`. This ADR MUST be
accepted before or with the merge of core#3345.

## Context

`compute/proxmox` downloads each Talos image into the datastore named by
`image_datastore_id`. That datastore MUST exist and MUST allow the `import`
content type. Nothing in Core creates it, so a first bootstrap on a new host
fails until the administrator runs `pvesm add dir` by hand. The plan-time check
in core#3347 reports the problem but does not fix it.

A datastore differs from the pool and the VMs in scope:

- Storage definitions live in `/etc/pve/storage.cfg`. They belong to the host,
  or to the cluster, and not to one context.
- Several contexts can share one host. If every context creates
  `windsor-images`, the second apply fails.
- `windsor destroy` on one context MUST NOT remove a storage that another
  context still uses.
- Creating storage needs `Datastore.Allocate` on `/storage`. The storage has no
  ACL path of its own before it exists.

These facts decide the design:

- A Windsor Terraform component accepts `destroy: false`. `windsor destroy`
  then skips the component. The `gitops` component already uses it. No `cli`
  change is needed.
- `dependsOn` orders a component before `compute`.
- A Terraform component has no `when` field. Only a facet has `when`, so an
  optional component needs its own facet.
- `bpg/proxmox` 0.116 has the resource `proxmox_storage_directory`. Its
  `create_base_path` argument creates the base directory. Its `nodes` argument
  lists the nodes where the storage is available.
- `compute/proxmox` already checks at plan time that the image datastore
  exists and allows `import`. A context that does not create the storage only
  needs to name it.

## Decision

### 1. A host component, not a datastore component

The new module is `terraform/host/proxmox`. The facet component is named
`host`. The datastore is the first object in it. Later host-level objects go in
the same module and the same state, and they follow the rules in sections 2
and 3.

### 2. Who owns an object

An object has one of three owners:

- A context owns it when one context uses it and it MUST go when the context
  goes. It belongs in `compute/proxmox`. VMs, downloaded images, and the pool
  (with `proxmox.create_pool`) are in this group.
- The host owns it when several contexts share it, or when it outlives any
  context. It belongs in the host component, which has `destroy: false`.
- The administrator owns it when Windsor only needs it to exist. It is a
  prerequisite. The module checks it at plan time and the README documents it.

### 3. Host-level objects are opt-in

Every host-level object MUST be opt-in. The default is to use what exists. A
default-on object would be hidden state that survives `windsor destroy`.

For the image datastore, the option is `proxmox.manage_image_datastore: true`.
The values `proxmox.image_datastore` (the storage id) and
`proxmox.image_datastore_path` (the directory on the node) MUST be set with it.
Composition fails when either is missing. Without the option, the facet adds no
component, and `compute/proxmox` behaves as before.

### 4. Users, roles, and ACLs are prerequisites

The module MUST NOT create users, roles, or ACLs. The administrator scopes the
Windsor user. A module that grants itself access removes that limit.

### 5. The image datastore

The module manages one directory storage with `proxmox_storage_directory`:

- `id` is `image_datastore_id`.
- `path` is `image_datastore_path`.
- `content` is `["import"]`.
- `create_base_path` is `true`.
- `nodes` is the `nodes` input, a list of node names. The facet passes
  `[proxmox.node]` today. With ADR-0025, it passes the full node list.

The facet adds the component only when the option is on. The `compute`
component gets a `dependsOn` entry for it only in that case. The plan-time
check from core#3347 still runs in `compute/proxmox`.

### 6. One context creates the storage, others reference it

Any one context MAY set the option and create the storage. That context owns it
in its own state. Other contexts on the host MUST NOT set the option. They set
`proxmox.image_datastore` to the same id, and the plan-time check in
`compute/proxmox` confirms that it exists and allows `import`. The module does
not import or adopt a storage. The creating context applies first.

### 7. Destroy never deletes the storage

The component has `destroy: false`, so `windsor destroy` skips it and clears its
state pointer. The resource has `lifecycle.prevent_destroy`, so a stray
`terraform destroy` or a replacement fails. Deleting the storage is a manual
step: `pvesm remove <id>`, then `rm -r` on the directory when the files are no
longer needed.

After destroy, the creating context has no state for the storage. A later apply
of that context fails because the storage exists. The user turns the option off
in that context and references the storage like any other context.

Images stay in the storage until the context that downloaded them destroys
`compute`. Each image file name ends with the context suffix, so two contexts
never share an image file. They share only the storage.

### 8. Privileges

Creating the storage needs `Datastore.Allocate` on `/storage` with propagation.
The path `/storage/<id>` does not exist before the first apply. The module
README and the `compute/proxmox` README state this. After the storage exists,
`compute/proxmox` needs the privileges that its README lists on `/storage/<id>`.

### 9. Scope

One context targets one host or one cluster. These are out of scope:

- Installing Proxmox and forming a cluster. The provider has no resource for
  either.
- Several standalone hosts in one context.

ADR-0025 covers placing VMs on several nodes of one cluster and one image
download for each node. Until it is implemented, the facet passes one node.
In a cluster, `nodes` on the storage MUST match the nodes that run VMs, and
more nodes need a change to the facet.

### 10. Kubernetes storage is a separate layer

The image datastore holds VM disks and images. App data uses the CSI driver in
`cluster.storage.driver`, which this ADR does not change. With the default
`openebs` driver, app data stays on the node of its VM, so VMs on several nodes
do not protect it. `longhorn` and `mayastor` replicate data across VMs. A
Proxmox CSI plugin is later work with its own ADR.

## Consequences

- A new Proxmox host bootstraps with no manual `pvesm add`, when the user sets
  the option and gives the Windsor user `Datastore.Allocate` on `/storage`.
- The storage survives `windsor destroy`. The administrator removes it by hand.
- Only the creating context holds the storage in its state. Other contexts need
  no state for it and no import.
- The creating context cannot apply again after a destroy until it references
  the storage instead of creating it.
- The option adds one component and one facet. The default path does not
  change.

## Open questions for the real-host test

The test runs on a Proxmox host with two contexts. It MUST answer these
questions before the work is done. If question 1 or 2 fails, the design needs a
change before merge.

1. Does `create_base_path = true` create the directory on the node?
2. Does a second context that only names the storage plan with no change, and
   pass the plan-time check?
3. Does creating the storage need a privilege beyond `Datastore.Allocate` on
   `/storage`, such as `Sys.Modify` on `/`?
4. Does `windsor destroy` on the creating context leave the storage and the
   other context's images in place?
5. Does a second apply of the creating context after destroy fail with a clear
   "already exists" error?

## Alternatives considered

A default-on datastore would remove one step for new users. It would also
create state that outlives `windsor destroy`, and it would fail on the second
context. The opt-in option keeps the default of using what exists.

Adopting an existing storage with an `import` block in each context would let
every context set the option. It needs a data source read, a content check, and
a state copy in each context, and the data source does not return the path, so
a path mismatch is not detectable at plan time. Naming the storage from the
other contexts needs none of that.

Putting the storage in `compute/proxmox` would need no new component. Destroy
of one context would then try to delete a storage that other contexts use, and
two contexts would race to create it.

Managing the Windsor user, role, and ACLs in the host component would make
setup shorter. It would also let the module widen its own access, which removes
the scope that the administrator sets.
