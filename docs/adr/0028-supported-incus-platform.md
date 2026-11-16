---
title: "ADR-0028: Incus becomes a supported platform"
description: Set the rules that move incus from community grade to supported. A managed bridge reports addresses from DHCP leases. A LAN network gets DHCP through an Incus guest agent extension on the Talos image, or explicit addresses. Windsor owns the signed Talos image feed. An IncusOS cluster lane gates the grade.
---

# ADR-0028: Incus becomes a supported platform

## Status

Proposed (2026-11-15). Builds on [ADR-0023](0023-node-addresses-from-dhcp-or-explicit.md),
which set the node address sources, and on [ADR-0026](0026-talos-node-pools.md),
which keeps `cluster.pools` off `incus`. [ADR-0008](0008-platform-hardening-parity.md)
sets the hardening gaps that section 8 lists.

Scope is the standalone `incus` platform (`workstation.runtime` unset).
The Colima workstation path keeps its behavior (section 7).

## Context

`incus` works on a developer machine. The standalone platform on an Incus
cluster has open defects ([core#2314](https://github.com/windsorcli/core/issues/2314),
[core#2319](https://github.com/windsorcli/core/issues/2319)) and no acceptance
test. Three questions block the support grade: how Core learns the guest
address, who provides the Talos image, and how a node gets Talos extensions.
The goal for a LAN network is DHCP with no address written by hand, as on
vSphere, Proxmox, and Hyper-V.

Facts checked against source (Incus at commit `9b1793d`, 2026-11-15):

- Incus has no reference to the QEMU guest agent. A search of `internal/` and
  `cmd/` for `guest agent` and `qemu-ga` returns no file. The agent that Incus
  uses is its own `incus-agent`, reached over vsock.
- For a VM with no `incus-agent`, `renderState` calls `getNetworkState`
  (`driver_qemu.go:11953`, `:13098`). Only NIC types that implement `NICState`
  answer, and two do: `nicBridged` (`nic_bridged.go:2131`) and `nicOVN`
  (`nic_ovn.go:1595`). `macvlan`, `physical`, and `sriov` have no fallback.
- `nicBridged.State` reads the network's `dnsmasq.leases` file for the NIC's MAC
  (`GetLeaseAddresses`, `network_utils.go:949`), then the host neighbor cache.
  Only a managed bridge has a lease file. The Incus maintainer confirms that an
  agentless VM relies on these leases, and that a guest-set static address leaves
  `incus list` empty ([lxc/incus#1579](https://github.com/lxc/incus/issues/1579)).
- When the agent reports a network, `renderState` uses it and skips the NIC
  fallback.
- The Incus Terraform provider ends `wait_for` `ipv4` when any interface other
  than `lo` has an `inet` address, in any scope (`resource_instance.go:2100`).
- `security.ipv4_filtering` exists only on `bridged` and `ovn` NICs. `ipv4.address`
  has no option on `macvlan`, `sriov`, or `physical` NICs
  ([NIC reference](https://linuxcontainers.org/incus/docs/main/reference/devices_nic/)).
- A cluster needs the same network defined on every member, and each member runs
  its own bridge and `dnsmasq`
  ([cluster networks](https://linuxcontainers.org/incus/docs/main/howto/cluster_config_networks/)).
- `siderolabs/extensions` has no Incus extension. Its guest agents are
  `hyperv`, `qemu`, `vmtoolsd`, `xen`, and `metal-agent`. Request
  [siderolabs/talos#9040](https://github.com/siderolabs/talos/issues/9040)
  closed as stale with no maintainer reply. Neither `siderolabs/talos` nor
  `siderolabs/image-factory` mentions Incus. Image Factory serves
  `metal-amd64.qcow2` and `metal-arm64.qcow2`
  (`internal/integration/download_test.go:796`), signs the installer images it
  makes, and documents no availability or support level for the public service.
- The Incus maintainer declines to host Talos images and points users to Image
  Factory ([lxc/lxc-ci#954](https://github.com/lxc/lxc-ci/issues/954)).
- `windsorcli/talos-incus` converts the Siderolabs `metal-<arch>.raw.zst` to
  qcow2, signs it with cosign, and serves it through a Cloudflare Worker at
  `images.windsorcli.dev`. The Worker adds the `Incus-Image-Hash` and
  `Incus-Image-URL` headers that Incus needs to import from a URL. Its README
  says the images are not for production.

Spike results (Colima, Incus 6.20, Talos v1.14.6 arm64, 2026-11-15):

- With no agent, a Talos VM on the managed bridge shows its lease address in
  `incus list`.
- The Talos kernel has no 9p (`CONFIG_NET_9P` is not set in `siderolabs/pkgs`).
  `virtio_fs`, `virtio_vsock`, and `virtio_console` are modules. ISO9660 and
  CD-ROM support are built in.
- Incus exports its built-in `config` and `agent` drives over 9p, which Talos
  cannot mount. A disk device with `source=agent:config` instead attaches an
  ISO9660 CD-ROM (label `incus-agent`) that Talos shows as `sr0`. It holds the
  `incus-agent` binary, the certificates, and the agent config.
- `machine.kernel.modules` loads `vmw_vsock_virtio_transport` and
  `virtio_console` with no reboot.
- A privileged pod mounted `sr0`, copied it to `/run/incus_agent`, and ran
  `incus-agent`. Incus connected over vsock, and `incus list` showed the guest
  interfaces and addresses.

The spike ran the agent as a pod, which exists only after Kubernetes starts. It
did not test an extension service, a NIC with no lease fallback, amd64, or a
start in maintenance mode.

## Decision

### 1. Address rule by network type

`incus.network` decides the rule. Core MUST NOT guess the NIC type from the
network name.

| `incus.network` | Address source | `wait_for_ipv4` |
|---|---|---|
| Unset (Core creates a NAT bridge) | The bridge DHCP lease that Incus reads. An explicit `ipv4` becomes `ipv4.address` on the NIC, a static lease by MAC. | `true` |
| Set, `network.dhcp: true` | DHCP from the LAN server. The guest agent reports the address to Incus. | `true` |
| Set, explicit `ipv4` per node | The declared address, reserved on the LAN DHCP server for the node MAC. | `false` |

The LAN rows follow ADR 0023: a LAN context needs `network.dhcp: true` or a full
node map in `cluster.controlplanes.nodes` and `cluster.workers.nodes`. The
`platform-incus.yaml` rules that today demand explicit addresses on every LAN
network change to match. The LAN DHCP row is available only when section 2
passes its gates. Until then the rule demands explicit addresses.

The module MUST wait for an address only when `wait_for_ipv4` is `true`. A
declared `ipv4` MUST NOT force a wait ([core#2314](https://github.com/windsorcli/core/issues/2314)).

The module MUST pass `ipv4_filtering_enabled` from the instance entry to the NIC
(core#2314). The default is `false`, because load balancer VIPs use addresses
that the filter blocks. The key applies only to a bridged NIC with a declared
address.

The module MUST pick the address Core uses from a `global` scope `inet` entry.
The provider ends its wait on any scope, so a link-local neighbor entry can
end the wait early.

### 2. The Incus guest agent extension

Incus never reads the QEMU guest agent, so the `siderolabs/qemu-guest-agent`
extension MUST NOT be used for `incus`. LAN DHCP needs `incus-agent` inside the
guest, which needs three parts:

- Core adds a disk device with `source=agent:config` to every VM. The compute
  module has no such device today.
- The Talos machine config loads `vmw_vsock_virtio_transport` and
  `virtio_console` through `machine.kernel.modules`, unless the extension
  loads them.
- A Talos system extension (`incus-guest-agent`) runs a service that mounts the
  CD-ROM labelled `incus-agent`, copies it to `/run/incus_agent`, and runs the
  `incus-agent` binary from it. The Incus host supplies that binary, so the
  extension builds and ships no Incus code.

The Windsor maintainers write the extension and submit it to
`siderolabs/extensions`. Core MUST NOT depend on a Windsor-only extension, because
Image Factory takes only registered extensions (section 4).

The LAN DHCP row of section 1 ships only after these gates pass:

1. The service starts in maintenance mode, before any machine config. Core
   needs the address to apply the config.
2. The service runs as an extension service, with the capability to mount
   ISO9660.
3. A VM on a `macvlan` network shows its address in `incus list`.
4. The same holds on `amd64` and after a Talos upgrade.

If gate 1 fails, LAN DHCP is dropped and a LAN network keeps explicit addresses.

### 3. Supported topologies

| Topology | Grade | Rule |
|---|---|---|
| One host, Core-created bridge | Supported | Section 1, first row. |
| One host, LAN network | Supported | Section 1, LAN rows. |
| Incus cluster, LAN network, `incus.targets` set | Supported | The same network MUST exist on every member. |
| Incus cluster, Core-created bridge | Rejected | Each member runs its own bridge and `dnsmasq`, so VMs on two members share a subnet but not a link. |
| OVN network | Not supported | The OVN NIC reports leases, so a later ADR MAY add it. |
| Colima workstation | Community | Section 7. |

Composition MUST fail when `incus.targets` names more than one member and
`incus.network` is unset. The message restates the user-side relationship:
"A cluster of Incus members needs incus.network set to a network that exists on
every member."

Core creates every object in the `default` project. `incus.project` is not
supported.

`cluster.pools` stays rejected on `incus` ([core#3422](https://github.com/windsorcli/core/issues/3422)).

### 4. Image source

Windsor owns the Talos image feed for `incus`. Siderolabs does not publish one.
`windsorcli/talos-incus` becomes the supported feed under these rules:

- The Windsor core team owns the repository, the Worker, and the signing
  identity.
- The build MUST take the Siderolabs `metal-<arch>.qcow2` from Image Factory for
  the schematic that holds `incus-guest-agent`, and MUST NOT convert from raw.
  Until the extension is registered with Image Factory, the feed uses the empty
  schematic and section 1 keeps explicit LAN addresses.
- A release for each new Talos version MUST publish for both `amd64` and
  `arm64` before Core pins that version.
- Each artifact MUST carry a cosign bundle. Incus checks the file hash, not the
  cosign bundle, so cosign is a manual check and the README says so.
- The README MUST drop the "not for production" notice when the first supported
  release ships.
- `cluster.controlplanes.image` and `cluster.workers.image` stay as the override
  for an air-gapped site that imports its own image.

Core stays on the `windsor:` remote.

### 5. Extensions reach a node by installer upgrade

A node gets Talos extensions through `cluster/talos/extensions`, which upgrades
the node to `factory.talos.dev/installer/<schematic>:v<version>`. This is the
path that Image Factory documents for replacing the installed extension set. The
schematic MUST always include `incus-guest-agent`, or the upgrade removes it.

- The upgrade MUST use `--reboot-mode powercycle` on `incus`. The nested VM does
  not complete a kexec reboot ([core#2319](https://github.com/windsorcli/core/issues/2319)).
- The step MUST do nothing when the node already runs the target schematic.
- The first boot and the upgrade reboot are one cost per node. A node replace
  repeats it.

### 6. Storage default

`openebs` stays the default, because it needs no extension. `longhorn` needs
`siderolabs/iscsi-tools` and `siderolabs/util-linux-tools`, which section 5
delivers. `longhorn` is supported on `incus` only after the acceptance lane
(section 9) passes with it.

### 7. The Colima workstation path

`workstation.runtime: colima` keeps `incusbr0`, the `local` pool, the `windsor:`
image, flannel, and the Colima defaults in `option-workstation.yaml`. It
receives the section 1 module fixes, because it shares `compute/incus`. It is
not covered by the acceptance lane and stays community grade.

### 8. Gaps against ADR 0008

| Capability | State on `incus` | Plan |
|---|---|---|
| STATE and EPHEMERAL disk encryption | Absent, as on every self-managed Talos platform | Follows ADR 0008 decision 1. No Incus change. |
| API server audit logging | Absent, as on every platform | Follows ADR 0008 decision 2. |
| Secure Boot | Off (the module sets `secureboot` to `false`) | Listed as a gap in the platform guide. |
| Etcd encryption | Absent | Follows ADR 0008 decision 1. |

These gaps are not Incus-specific. Hyper-V, Proxmox, and vSphere ship with the
same gaps, so they do not block the grade. The platform guide MUST list them.

### 9. Acceptance lane

The `acceptance` repo gets an `incus` context on an IncusOS cluster. The lane
runs `windsor up`, replaces one node, upgrades Talos with `windsor upgrade node`,
and runs `windsor down`. It uses a LAN network. IncusOS names its default pool
`local`, so the context sets `incus.storage_pool: local`.

The lane needs a host. The ADR proposes a maintainer-owned IncusOS cluster with
a self-hosted runner. CI MUST NOT select the context on a pull request, the same
rule as the `hyperv` context. A maintainer dispatches it before a release.

The support grade changes to supported only after the lane passes on the
release pair. Until then `incus` stays community grade.

## Consequences

- One address table covers a managed bridge and a LAN, and it fits in the platform
  guide.
- LAN DHCP depends on an extension that Siderolabs must accept. Until it ships,
  a LAN network needs explicit addresses.
- Windsor carries the cost of a signed image feed. A missed Talos release blocks
  `incus` users from the new version.
- A node that needs an extension reboots once after first boot.
- A cluster needs a LAN network. A single-host user keeps the zero-setup bridge.
- A user with `incus.targets` and no `incus.network` fails composition after
  this ADR ships.

## Alternatives considered

An explicit `ipv4` on every network, including the bridge. This removes the lease
read but makes the zero-setup single-host case write addresses by hand. It also
gives up the LAN DHCP goal.

The agent as a Kubernetes DaemonSet. It runs only after the cluster exists, so
it cannot report the address that Core needs to apply the machine config.

A `cloud-init:config` static address for LAN nodes. Incus attaches an ISO with
the `cidata` label and Talos `nocloud` reads it, so Core could set the address.
It needs the `nocloud` image and still needs a declared address per node. It
stays an open option for sites that refuse the extension.

A Core-created bridge on a cluster. The members do not share a link, so it
cannot carry one cluster.

Per-schematic images imported by Core. The Factory `metal-<arch>.qcow2` URL takes
a schematic, so a node would boot with its extensions and skip the upgrade
reboot. The Incus provider's `incus_image` takes a local file, and Incus URL
import needs the hash headers that only the Worker adds. Core would need a local
download and a metadata archive for each schematic. That adds a multi-step local
command that the provisioner rule forbids, and it pulls hundreds of megabytes on
every operator machine. A later ADR MAY revisit it if the reboot cost matters.

Waiting for Siderolabs or Incus to publish a feed. Neither publishes one today,
so the platform would stay community grade with no end date.

## References

- Incus source: `internal/server/instance/drivers/driver_qemu.go`,
  `internal/server/device/nic_bridged.go`, `internal/server/device/disk.go`,
  `internal/server/network/network_utils.go`.
- terraform-provider-incus: `internal/instance/resource_instance.go`.
- siderolabs/image-factory: `internal/integration/download_test.go`.
- siderolabs/pkgs: `kernel/build/config-arm64`, `kernel/build/config-amd64`.
- Talos: [Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory).
- `terraform/compute/incus/`, `contexts/_template/facets/platform-incus.yaml`,
  `contexts/_template/facets/option-storage.yaml`.
