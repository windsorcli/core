---
title: "ADR-0029: Incus host layer and one project per context"
description: Split an Incus cluster into a host layer that one context owns and a project for each context's cluster stack. Amends ADR-0028 section 3, which put every object in the default project.
---

# ADR-0029: Incus host layer and one project per context

## Status

Proposed (2026-11-15). Amends [ADR-0028](0028-supported-incus-platform.md)
section 3, which says "Core creates every object in the `default` project.
`incus.project` is not supported." Sections 2 and 3 below replace that rule.
The rest of ADR-0028 stands.

Scope is the standalone `incus` platform (`workstation.runtime` unset). The
Colima workstation path keeps the `default` project.

## Context

One Incus cluster can carry more than one Talos cluster. The loft cluster
runs the `home` context today, and a second context MAY follow. The first
context sets up the cluster and builds its own stack. A later context
targets the same cluster and builds only its stack.

`host/incus` holds the server-scoped objects: the storage pool,
the `physical` LAN network, the per-member image, backup, and log storage keys,
projects, and trusted certificates. One context sets `incus.host` and owns
them. Other contexts leave `incus.host` unset.

Facts from `main` and the Incus docs and source:

- `compute/incus` names instances from their position in the pool:
  `controlplane`, `controlplane-1`, `worker`, `worker-1`
  (`terraform/compute/incus/main.tf`). The names carry no context id. Two
  contexts in the `default` project ask for the same instance name, and the
  second apply fails.
- `compute/hyperv` and `compute/proxmox` add `-<id>` to each VM name, because
  those hosts have one namespace for VM names.
- Incus scopes instance names, profiles, images, and custom storage volumes to
  a project. A new project starts with `features.images`,
  `features.profiles`, `features.storage.volumes`, and
  `features.storage.buckets` set to `true`
  ([projects](https://linuxcontainers.org/incus/docs/main/reference/projects/)).
- `features.networks` needs OVN. A project without it uses the networks of the
  `default` project, so the `physical` LAN network stays shared.
- Storage pools and certificates are server-wide. Only an unrestricted client
  can create a project or a certificate. A client restricted to a project
  cannot list certificates.
- A new project's `default` profile has no devices. `compute/incus` sets the
  `root` disk and `eth0` NIC on each instance
  (`terraform/compute/incus/modules/instance/main.tf`), so it needs nothing
  from the profile.
- `raw.qemu` is blocked in a project with `restricted=true`, through
  `restricted.virtual-machines.lowlevel`. `compute/incus` sets `raw.qemu` on
  every Talos VM. A certificate restricted to a project is a different control:
  it limits which projects the client reaches, not what a project allows.
- Incus deletes only an empty project. Cached images count. The provider's
  `force_destroy` on `incus_project` deletes the contents first.
- `cluster/talos` sets no hostname (`terraform/cluster/talos/modules/machine/main.tf`).
  Talos ignores the `user.hostname` key that the facet sets on each instance.
  The Talos default `HostnameConfig` is `auto: stable`, which derives a name
  such as `talos-abc-xyz` from the machine identity. A static `hostname` in
  `HostnameConfig` outranks DHCP and the automatic name, and it conflicts with
  `auto` in the same document
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

One context per Incus cluster MUST set `incus.host`. That context owns the
host objects in its state and applies first. A context that targets the same
cluster MUST set the same `incus.remote`, `incus.network`, and
`incus.storage_pool`, and MUST leave `incus.host` unset. The `host` step runs
with `destroy: false`, and the pool and network have `prevent_destroy`.

An object belongs to the host layer when only the server holds it, or when
only an unrestricted client can create it. Every other object belongs to the
context.

| Object | Layer |
|---|---|
| Storage pool, `physical` network, `storage.*_volume` keys and volumes | Host |
| Projects that a restricted client uses, and all certificates | Host |
| The context's own project, when an unrestricted client applies it | Context |
| Profiles, cached images, custom volumes, instances, network zones | Context |

Core manages no cluster groups and no network ACLs. `incus.targets` names
members. ACLs apply to managed bridge and OVN networks, and the LAN network is
neither.

### 2. One project per context

`incus.project` names the project for the context's stack. The default is the
context `id`, not the context name, because the name can repeat across
repositories on one Incus cluster. `compute/incus` passes the project to every instance, image,
and custom volume.

`incus.create_project` decides who creates it. The default is `true`, and
`compute/incus` creates the project with `force_destroy`, so `windsor destroy`
removes the stack and its cached images. Creating a project needs an
unrestricted client.

A context that runs with a restricted certificate MUST set
`incus.create_project: false`. The host-owning context then lists the project
in `incus.host.projects` and the certificate in `incus.host.certificates`, and
applies first. Adding that kind of context means one change to the
host-owning context.

Two contexts MUST NOT share a project. Composition cannot check this, because
it sees one context at a time. The platform guide MUST state it.

### 3. Project settings

Core MUST NOT set `restricted=true` on a project, because it blocks the
`raw.qemu` key that every Talos VM sets. Core leaves the `features.*` keys at
their initial values. `features.networks` stays `false`, so the project uses
the `default` project's networks.

The NAT bridge that `compute/incus` creates without `incus.network` MUST go in
the `default` project, because a project without `features.networks` holds no
networks.

### 4. Names

Instance names stay as they are: `controlplane`, `worker-1`, and so on. The
project scopes them, so they need no `-<id>` suffix.

Core MUST set a static Talos hostname on every `incus` node through a
`HostnameConfig` patch, in place of `auto: stable`. The hostname is the node's
`hostname` in `cluster.controlplanes.nodes` or `cluster.workers.nodes` when
set. Otherwise it is the pool position name with the context `id` as a
suffix: `controlplane-1-<id>`, `worker-1-<id>`. A user who wants readable names
sets `id` (for example `id: home` gives `controlplane-1-home`).

A hostname is one DNS label of at most 63 characters, and `id` alone MAY be
63. The suffix MUST be truncated and hashed to fit, with the rule
`compute/incus` uses for network names. The instance `user.hostname` key MUST
carry the same value, so the compute output matches the node.

The result is a readable Kubernetes node name that is unique on a shared LAN,
including in a router's DNS of DHCP hostnames.

### 5. Images

The Talos image belongs to the context. Each project caches its own copy, so
two contexts can pin different Talos versions, and the copy goes with the
project. Each new project fetches the image once from
`images.windsorcli.dev`. The compute step keeps `parallelism: 1` for the
rate limit.

## Consequences

- A second context on the cluster sets four keys and leaves `incus.host`
  unset.
- A context under a restricted certificate needs an entry in the host-owning
  context first.
- Each project holds its own copy of the Talos image.
- Node names carry the context `id`. With a generated `id`, they read as
  `worker-1-w4p4bode` until the user sets `id`.

## Alternatives considered

A `-<id>` suffix on instance names in the `default` project, as on Hyper-V and
Proxmox. It avoids the collision but leaves profiles, images, and volumes
shared, and a restricted certificate cannot be scoped to one context.

Every project in the host layer. It works under a restricted certificate, but
every new context then needs a change to the host-owning context, even when
an unrestricted client applies it.

A project that each context always creates. A restricted certificate cannot
create a project, so CI under one would fail.

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
  [physical network](https://linuxcontainers.org/incus/docs/main/reference/network_physical/),
  [network ACLs](https://linuxcontainers.org/incus/docs/main/howto/network_acls/).
- Incus source: `internal/server/device/nic_physical.go`,
  `internal/server/device/nictype/nictype.go`.
- terraform-provider-incus 1.2.1: `docs/resources/project.md`,
  `docs/resources/certificate.md`.
