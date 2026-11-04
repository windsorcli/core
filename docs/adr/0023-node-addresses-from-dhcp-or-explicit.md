---
title: "ADR-0023: Node addresses come from DHCP or an explicit value"
description: Remove the network.cidr_block offsets that gave vSphere, Proxmox, Hyper-V, and Incus nodes a default address, and fail composition when a pool has neither DHCP nor declared addresses.
---

# ADR-0023: Node addresses come from DHCP or an explicit value

## Status

Proposed (2026-11-03). Builds on [ADR-0019](0019-explicit-endpoints-dhcp-and-tls-sources.md),
which made gateway endpoints explicit and added `network.dhcp` control planes.
Scope is `vsphere`, `proxmox`, `hyperv`, and `incus` without a workstation.
Section 6 keeps the derived addresses for Hyper-V NodePort NAT.
Workstation contexts (`option-workstation.yaml`, `terraform/workstation/docker`)
are out of scope.

## Context

When `network.dhcp` is false and a node has no entry in
`cluster.controlplanes.nodes` or `cluster.workers.nodes`, Core computes its
address from `network.cidr_block`:

| Platform | Control plane N | Worker N | Source |
|---|---|---|---|
| vSphere, Proxmox, Hyper-V LAN | `cidrhost(cidr_block, 9 + N)` | `cidrhost(cidr_block, 19 + N)` | `platform-<name>.yaml` `<name>_controlplanes`, `<name>_workers` |
| Incus | `cidrhost(cidr_block, 10)`, counted up by the module | `cidrhost(cidr_block, 20)`, counted up by the module | `platform-incus.yaml` compute `instances` |

On vSphere, Proxmox, and Hyper-V with `net_adapter`, `cidr_block` is a LAN
that Core attaches to. Core has no idea which of its addresses are free. A
default of `.10` can be a printer, another cluster's control plane, or an
address the DHCP server hands out. Nothing in `values.yaml` shows the
address either. The operator has to know the offset rule to find their own
nodes.

The offsets also break as soon as a pool grows past ten: control plane 11
lands on worker 1.

## Decision

### 1. Two sources for a node address

A node on these platforms MUST take its address from one of:

- DHCP, with `network.dhcp: true`. Compute reports each leased address to the
  cluster step.
- An explicit entry in `cluster.controlplanes.nodes` or `cluster.workers.nodes`,
  keyed by pool position (`controlplane-1` to `controlplane-N`, `worker-1` to
  `worker-N`). The entry's `node` value, or the host part of `endpoint`, is the
  guest address.

Core computes no node address from `network.cidr_block`. `network.gateway`
keeps its `cidrhost(cidr_block, 1)` default, because it names the router and
not a node.

### 2. Composition fails when a pool has neither

Each of the four facets carries two `requires` rules, one per pool. A rule
fires when `network.dhcp` is not true and at least one position from 1 to
`count` has no entry:

```text
the following required values are not set in values.yaml:

  - cluster.controlplanes.nodes.controlplane-N

Notes:

  cluster.controlplanes.nodes.controlplane-N:
    Set network.dhcp to true, or give each control plane an address in cluster.controlplanes.nodes under controlplane-1 to controlplane-N.
```

The path `controlplane-N` is a placeholder that no valid key can match, since
node keys are lowercase DNS labels. A partial map fails the same way as an
empty one. On Hyper-V the rules skip NodePort NAT, and on Incus they skip
contexts with `workstation.runtime` set.

The existing ADR-0019 rule stays: DHCP with more than one control plane
requires `cluster.endpoint` on vSphere, Proxmox, and Hyper-V.

### 3. Every platform reports DHCP addresses

Removing the fallback is safe only where compute returns each leased address
to the cluster step. All four do:

| Platform | How compute reads the lease |
|---|---|
| vSphere | The Talos schematic carries `siderolabs/vmtoolsd-guest-agent`. For a guest with no `ipv4`, `vsphere_virtual_machine` waits on `wait_for_guest_net_timeout`, and the module reads `guest_ip_addresses`. |
| Proxmox | The schematic carries `siderolabs/qemu-guest-agent`. For a guest with no `ipv4`, the agent's `wait_for_ip` waits for an IPv4 address, and the module reads `ipv4_addresses`. |
| Hyper-V | The schematic carries `siderolabs/hyperv-guest-agent`. The module waits `guest_ipv4_timeout`, reads `hyperv_vm_state.ip_addresses`, and falls back to `network_adapter[0].ip_addresses`. |
| Incus | The module creates the bridge with `ipv4.dhcp` on. Each instance without `ipv4` waits on `wait_for` `ipv4`, and the module reads the instance's address. |

No platform needs a rule that forbids DHCP.

On Incus, a declared address becomes the NIC's `ipv4.address`, which the
bridge serves as a static DHCP lease. `security.ipv4_filtering` applies only to
a NIC with a declared address, as before.

### 4. Hyper-V LAN nodes MAY pin a MAC

`cluster.controlplanes.nodes.<key>.mac_address` and the worker equivalent set
the guest NIC's MAC on Hyper-V and Proxmox. An operator who wants DHCP with a
stable address creates a reservation on the router for that MAC and sets
`network.dhcp: true`. Unset, the hypervisor assigns the MAC.

terraform-provider-hyperv v0.6.0 adds `wait_for_guest_ip_timeout` on
`hyperv_vm` and a `hyperv_virtual_switch` data source for an existing External
switch. That release is a draft as of this ADR, and the Hyper-V NAT work owns
the provider upgrade. The module keeps its `time_sleep` and `hyperv_vm_state`
wait until then. The upgrade changes how the module waits, not which addresses
it reports.

### 5. Incus builds one instance per node

`platform-incus.yaml` passes one compute instance per pool position instead of
one counted entry per pool, so each node can carry its own address. Instance
names keep the module's previous pattern: `controlplane` for a single node,
`controlplane-0` to `controlplane-(N-1)` for several, and the same for
workers. Existing Incus VMs keep their names.

### 6. Hyper-V NodePort NAT nodes keep derived addresses

When both gateways are NodePort, Hyper-V puts the guests on a NetNat switch
inside `network.cidr_block`. Core creates that switch and its subnet, and only
Core's guests use it. The LAN collision that sections 1 and 2 remove cannot
occur there.

On NAT, control plane N keeps `cidrhost(cidr_block, 9 + N)` and worker N keeps
`cidrhost(cidr_block, 19 + N)`. The `requires` rules of section 2 do not apply.
`windsor init` writes no node entries, so a new NAT context composes without
them.

## Upgrading a v0.8.0 context

A v0.8.0 context on these platforms that set neither `network.dhcp` nor a full
nodes map fails composition after the upgrade. Its nodes already hold the
offset addresses, so the change that keeps the cluster as it is writes those
addresses into `values.yaml`. For `cidr_block: 10.5.0.0/16`, three control
planes and two workers:

```yaml
cluster:
  controlplanes:
    count: 3
    nodes:
      controlplane-1: { node: 10.5.0.10, endpoint: 10.5.0.10:50000 }
      controlplane-2: { node: 10.5.0.11, endpoint: 10.5.0.11:50000 }
      controlplane-3: { node: 10.5.0.12, endpoint: 10.5.0.12:50000 }
  workers:
    count: 2
    nodes:
      worker-1: { node: 10.5.0.20, endpoint: 10.5.0.20:50000 }
      worker-2: { node: 10.5.0.21, endpoint: 10.5.0.21:50000 }
```

Control plane N had `cidrhost(cidr_block, 9 + N)` and worker N had
`cidrhost(cidr_block, 19 + N)`. Keys use the position even when `count` is 1.
These entries give each guest the address it already holds.

Switching to `network.dhcp: true` instead also composes, but each guest takes
whatever lease the DHCP server offers, and the cluster's node addresses change.

## Consequences

- Every node address on these platforms appears in `values.yaml` or comes from
  the site's DHCP server. Core picks one only on a Hyper-V NodePort NAT subnet,
  which Core creates.
- A context for these platforms with neither `network.dhcp: true` nor a nodes
  map no longer composes, so `windsor init` defaults for them need one of the
  two.
- Hyper-V on an Internal switch without NodePort has no DHCP server, so its
  nodes need explicit addresses.
- The per-node `mac_address` field is honored on Hyper-V and Proxmox only. The
  vSphere module has no MAC input.
- The Incus module drops its unused `ip_start_offset` and
  `instance_sequential_ips` locals.

## Alternatives considered

Keeping the offsets and only documenting them leaves the collision on a shared
LAN in place. The operator still learns the addresses from a rule rather than
from their own file.

Defaulting Incus to DHCP, since Core owns the bridge, would make one platform
read `network.dhcp: false` differently from the others. One rule for all four
is easier to state in an error message.

Requiring explicit addresses on Hyper-V NodePort NAT too would make the four
platforms read the same way. It would also fail every new NAT context until the
operator writes a node list, or make `windsor init` copy Core's offsets into the
CLI. Neither buys anything on a subnet that only Core's guests use.
