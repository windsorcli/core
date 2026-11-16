---
title: "ADR-0029: Incus host layer, LAN bridge, and one project per context"
description: One context per Incus cluster creates the shared storage pool. Every context attaches its VMs to a host bridge named lan by default and builds its stack in its own project. Amends ADR-0028 section 3.
---

# ADR-0029: Incus host layer, LAN bridge, and one project per context

## Status

Proposed (2026-11-15). Amends two rules in [ADR-0028](0028-supported-incus-platform.md)
section 3:

- "Core creates every object in the `default` project. `incus.project` is not
  supported." Section 4 below replaces it.
- "Composition MUST fail when `incus.targets` names more than one member and
  `incus.network` is unset." Section 2 below replaces it with a default.

The rest of ADR-0028 stands. Scope is the standalone `incus` platform
(`workstation.runtime` unset). The Colima workstation path keeps the `default`
project and its NAT bridge.

## Context

One Incus cluster can carry more than one Talos cluster. The loft cluster runs
the `home` context, and a second context MAY follow. The first context sets up
what the cluster shares and builds its own stack. A later context targets the
same cluster and builds only its stack.

Facts from `main` and the Incus, IncusOS, and Talos docs and source:

- A storage pool on an Incus cluster is defined on each member with its
  member-specific `source`, then created once for the cluster
  ([cluster storage](https://linuxcontainers.org/incus/docs/main/howto/cluster_config_storage/)).
  The provider cannot import a clustered pool, so one layer MUST create it.
- The provider's `incus_cluster` data source lists the cluster members by
  name. The provider has no data source that lists a member's bridges.
- IncusOS makes a bridge for each interface that has the `instances` role, and
  names the bridge after the interface. The interface `name` in the IncusOS
  network config is free text, and `hwaddr` binds it to the hardware
  ([IncusOS network](https://linuxcontainers.org/incus-os/docs/main/reference/system/network/)).
  The same `name` on every member gives the same bridge name on every member.
- An instance NIC with `nictype=bridged` and `parent=<bridge>` attaches to a
  host bridge by name, managed by Incus or not. Incus runs no DHCP on a bridge
  it does not manage.
- `compute/incus` names instances from their position in the pool:
  `controlplane`, `controlplane-1`, `worker`, `worker-1`. The names carry no
  context id. Two contexts in one project ask for the same instance name, and
  the second apply fails.
- Incus scopes instance names, profiles, images, and custom storage volumes to
  a project. A new project starts with `features.images`,
  `features.profiles`, `features.storage.volumes`, and
  `features.storage.buckets` set to `true`
  ([projects](https://linuxcontainers.org/incus/docs/main/reference/projects/)).
  `features.networks` needs OVN. A project without it uses the networks of the
  `default` project.
- A new project's `default` profile has no devices. `compute/incus` sets the
  `root` disk and `eth0` NIC on each instance, so it needs nothing from the
  profile.
- `restricted=true` on a project blocks `raw.qemu` through
  `restricted.virtual-machines.lowlevel`. `compute/incus` sets `raw.qemu` on
  every Talos VM.
- Incus deletes only an empty project, and cached images count. The provider's
  `force_destroy` on `incus_project` deletes the contents first.
- Only an unrestricted client can create a project or a certificate.
- `cluster/talos` sets no hostname. Talos ignores the `user.hostname` key that
  the facet sets on each instance. The Talos default `HostnameConfig` is
  `auto: stable`, which derives a name such as `talos-abc-xyz` from the machine
  identity. A static `hostname` in `HostnameConfig` outranks DHCP and the
  automatic name, and it conflicts with `auto` in the same document
  ([HostnameConfig](https://docs.siderolabs.com/talos/v1.14/reference/configuration/network/hostnameconfig)).
  The Talos hostname is also the Kubernetes node name.
- The context name (`local`, `home`) is the folder name, and two repositories
  can use the same one. `id` is a DNS label in `values.yaml`. When it is
  unset, `windsor init` generates `w` and seven random characters.
  `compute/hyperv` and `compute/proxmox` suffix VM names with `-<id>`.

## Decision

### 1. Host layer

`host/incus` is the host layer. The name follows `host/proxmox`. `platform`
already names the facet that selects the platform (`platform: incus`).

The host layer creates the storage pool `incus.storage_pool` (default
`default`) on every member, with the ZFS dataset `incus.host.dataset` as its
source. It reads the members from the cluster, so a member that joins later
gets the pool on the next apply.

One context per Incus cluster MUST set `incus.host`. That context owns the pool
in its state and applies first. A context that targets the same cluster MUST
set the same `incus.remote` and `incus.storage_pool`, and MUST leave
`incus.host` unset. The `host` step runs with `destroy: false`, and the pool
has `prevent_destroy`.

| Object | Owner |
|---|---|
| Storage pool | Host layer |
| LAN bridge | IncusOS bootstrap (section 2) |
| Trusted operator certificate | IncusOS bootstrap |
| Project, profiles, cached images, custom volumes, instances | Context (section 4) |

Core manages no cluster groups, no network ACLs, and no
`storage.images_volume`, `storage.backups_volume`, or `storage.logs_volume`
keys. `incus.targets` names members. ACLs apply to managed bridge and OVN
networks, and the LAN bridge is neither. The storage keys are IncusOS server
housekeeping, set at install.

### 2. LAN bridge

`incus.network` names a host bridge that exists under the same name on every
member that hosts a VM. `compute/incus` attaches each VM to it as a bridged NIC
and creates no network. Core MUST NOT guess a member's bridge.

When `incus.targets` names more than one member, the default is `lan`. A
cluster cannot use the NAT bridge that Core creates, so `lan` is the only
working default. The IncusOS bootstrap MUST name the instances interface `lan`
on every member, or the context MUST set `incus.network` to the name it uses.
With one member or no `incus.targets`, unset `incus.network` keeps the NAT
bridge.

The address rules of ADR-0028 section 1 apply: on the LAN bridge, each node
declares its address, reserved on the LAN DHCP server.

### 3. Network objects outside Core

Core creates no `physical` network for the LAN. A `physical` network with a
per-member `parent` would only map different bridge names to one name, and the
same name on every member removes that need.

### 4. One project per context

`incus.project` names the project for the context's stack. The default is the
context `id`, not the context name, because the name can repeat across
repositories on one cluster. `compute/incus` creates the project with
`force_destroy` and passes it to every instance, image, and custom volume, so
`windsor destroy` removes the stack and its cached images. Creating a project
needs an unrestricted client.

Core MUST NOT set `restricted=true` on a project, because it blocks the
`raw.qemu` key that every Talos VM sets. Core leaves the `features.*` keys at
their initial values. `features.networks` stays `false`, so the project uses
the `default` project's networks. The NAT bridge that `compute/incus` creates
on a single host MUST go in the `default` project.

Two contexts MUST NOT share a project. Composition cannot check this, because
it sees one context at a time. The platform guide MUST state it.

A context that runs under a certificate restricted to its project cannot
create that project. Core does not support that case. A later ADR MAY add it,
with the project and certificate created by the host-owning context.

### 5. Names

Instance names stay as they are: `controlplane`, `worker-1`, and so on. The
project scopes them, so they need no `-<id>` suffix.

Core MUST set a static Talos hostname on every `incus` node through a
`HostnameConfig` patch, in place of `auto: stable`. The hostname is the node's
`hostname` in `cluster.controlplanes.nodes` or `cluster.workers.nodes` when
set. Otherwise it is the pool position name with the context `id` as a suffix:
`controlplane-1-<id>`, `worker-1-<id>`. A user who wants readable names sets
`id` (for example `id: home` gives `controlplane-1-home`).

A hostname is one DNS label of at most 63 characters, and `id` alone MAY be
63. The suffix MUST be truncated and hashed to fit, with the rule
`compute/incus` uses for network names. The instance `user.hostname` key MUST
carry the same value, so the compute output matches the node.

The result is a readable Kubernetes node name that is unique on a shared LAN,
including in a router's DNS of DHCP hostnames.

### 6. Images

The Talos image belongs to the context. Each project caches its own copy, so
two contexts can pin different Talos versions, and the copy goes with the
project. Each new project fetches the image once from
`images.windsorcli.dev`. The compute step keeps `parallelism: 1` for the rate
limit.

## Consequences

- A cluster context sets `incus.remote`, `incus.targets`, and node addresses.
  The host-owning context also sets `incus.host.dataset`.
- The IncusOS bootstrap names the instances interface `lan` on each member.
  Renaming it recreates the bridge and drops what is on it, including the
  management address when it shares that interface.
- Each project holds its own copy of the Talos image.
- Node names carry the context `id`. With a generated `id`, they read as
  `worker-1-w4p4bode` until the user sets `id`.
- CI under a restricted certificate is not supported.

## Alternatives considered

A `physical` network with a per-member `parent` and a map of bridge names in
`values.yaml`. It works with the IncusOS default names, but it adds a host
object and a per-member map that one shared bridge name removes.

`uplink` as the default bridge name. Incus uses "uplink network" for the
network that an OVN network routes through, so the name suggests OVN.

A `-<id>` suffix on instance names in the `default` project, as on Hyper-V and
Proxmox. It avoids the collision but leaves profiles, images, and volumes
shared.

Projects and restricted certificates in the host layer. They allow CI under a
restricted certificate, but every new context then needs a change to the
host-owning context, and no context needs it yet.

`features.networks` per project. It needs OVN, which ADR-0028 does not
support.

The Talos `auto: stable` hostname. It is unique with no change, but
`talos-abc-xyz` does not match `incus list` or the pool position.

A hostname with no suffix (`controlplane-1`). It is readable, but two contexts
on one LAN register the same DHCP hostname.

A suffix from the context name. The name is readable but can repeat across
repositories.

## References

- `terraform/host/incus/`, `terraform/compute/incus/`,
  `contexts/_template/facets/platform-incus.yaml`.
- Incus: [projects](https://linuxcontainers.org/incus/docs/main/reference/projects/),
  [cluster storage](https://linuxcontainers.org/incus/docs/main/howto/cluster_config_storage/),
  [network ACLs](https://linuxcontainers.org/incus/docs/main/howto/network_acls/).
- IncusOS: [network](https://linuxcontainers.org/incus-os/docs/main/reference/system/network/).
- terraform-provider-incus 1.2.1: `docs/data-sources/cluster.md`,
  `docs/resources/storage_pool.md`, `docs/resources/project.md`.
