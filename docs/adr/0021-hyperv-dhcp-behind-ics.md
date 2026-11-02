---
title: "ADR-0021: Hyper-V DHCP guests behind an ICS network"
description: In NodePort mode, Hyper-V guests lease addresses from an ICS network in place of a NAT switch with static addresses. Host port proxies forward to the address each guest reports.
---

# ADR-0021: Hyper-V DHCP guests behind an ICS network

## Status

Proposed.

## Context

When both gateways use `NodePort`, `platform-hyperv` puts the VMs
behind NAT on the Hyper-V host. Today the `compute/hyperv` module
creates a `hyperv_virtual_switch` of type `NAT`. That switch is an
Internal switch plus a Windows `NetNat` instance on `network.cidr_block`.

The facet gives each guest a static address from `network.cidr_block`.
The host vNIC takes `.1`, control planes take `.10` and up, and
workers take `.20` and up. The facet writes each address in three
places: the Talos machine config, the CIDATA `network-config`, and a
`hyperv_nat_static_mapping` per forwarded port.

This design has these problems:

- `NetNat` has no DHCP server, so every address is a fixed offset.
  More than ten control planes collide with the worker range.
- Windows supports one `NetNat` per host in practice. Two contexts on
  one host (core#2757) cannot each have a NAT switch.
- `Add-NetNatStaticMapping` rejects external ports in the dynamic port
  range, 49152 and up.
- The facet, not the host, decides the guest address. The facet cannot
  see a conflict on the host.

The `windsorcli/hyperv` provider now has the resources for a different
design (windsorcli/terraform-provider-hyperv#423):

- `hyperv_ics_network` manages a Host Compute Network of type ICS. The
  host gives each guest a DHCP lease, DNS, and outbound NAT.
- `hyperv_vm.wait_for_guest_ip_timeout` makes VM creation wait until
  the guest reports an IPv4 address (provider #436).
- `hyperv_port_proxy` manages a `netsh interface portproxy` rule and
  its firewall rule (provider #438).

## Decision

### 1. An ICS network replaces the NAT switch

In NodePort mode, `platform-hyperv` sets `switch_type: ICS`.
`compute/hyperv` then creates one `hyperv_ics_network` and no
`hyperv_virtual_switch`. The network is named `windsor-<context>`, and
its address prefix is `network.cidr_block`.

Every ICS network on a host shares one Internal switch. HNS gives each
network a VLAN isolation ID. The module attaches each VM NIC to the
network's `switch_name` with the network's `isolation_id`, which it
reads from the resource. The module does not assume the switch name.

The module removes the `NAT` switch type and its `nat_name`,
`nat_internal_address_prefix`, and `nat_host_address` inputs.

### 2. Guests use DHCP

In NodePort mode, `hyperv_effective.dhcp` is true. The Talos network
patch sets `dhcp: true`, and the CIDATA `network-config` sets
`dhcp4: true`. The facet sets no guest addresses and no gateway.

`cluster.endpoint` is still the host address, so it is known before
the VMs exist. The compute step still signs the machine config into
the CIDATA seed, and `cluster/talos` skips the config apply.

The guests use `network.nameservers` (default `1.1.1.1` and `8.8.8.8`)
through the host NAT. The ICS lease also gives a DNS server, the ICS
host address, and the search domain `mshome.net`.

### 3. Port proxies follow the reported address

`hyperv_port_proxy` replaces `hyperv_nat_static_mapping`. Each forward
names its target VM by instance name, not by address:

- `port_forward_target` is the default target, `controlplane-1`.
- `port_forward_target_overrides` maps a listen port to an instance
  name. The facet uses it for the per-node Talos API forwards.

The module reads `connect_address` from the first IPv4 entry of
`hyperv_vm.instances[...].network_adapter[0].ip_addresses`. A refresh
reads the current address, so the next apply moves a forward to a new
lease.

Each DHCP VM sets `wait_for_guest_ip_timeout` to `guest_ipv4_timeout`
(default `5m`). VM creation returns only when the guest has an IPv4
address. The module removes its `time_sleep` and its
`hyperv_vm_state` read, and the `hashicorp/time` provider.

The forwards listen on the host address from `cluster.endpoint`, not
on `0.0.0.0`.

The listen ports do not change. The API is on `6443`. The Talos API of
control plane N is on `40000+N-1`, and of worker N on `40100+N-1`.
Gateway node ports and `gateway.publish_ports` forward as before.

### 4. `cluster/talos` reads node addresses from compute

In NodePort mode, the facet builds each `cluster/talos` node from two
sources. The `endpoint` is the node's host forward, such as
`192.168.3.77:40000`. The `node` is the address that compute reports
for the VM with the same hostname. `talosctl` connects to the endpoint
and addresses the node by its guest address.

### 5. `network.cidr_block` is the ICS prefix

In NodePort mode, `network.cidr_block` is the DHCP prefix of the ICS
network. It MUST be a network address with a prefix of `/30` or
shorter. It MUST NOT overlap another network on the host. The default,
`10.5.0.0/16`, applies when it is unset. The facet no longer derives
guest addresses or a gateway from it.

### 6. TCP only

`hyperv_port_proxy` forwards TCP only, because `netsh portproxy` has no
UDP mode. The module removes `udp_port_forwards`,
`extra_udp_port_forwards`, and the `udp_port_forwards` output.

No facet sets a UDP forward, so no Windsor feature uses one. In
NodePort mode the private DNS add-on is off already (see
`platform-hyperv`), so DNS on UDP 53 is not forwarded today. A
blueprint that sets `udp_port_forwards` on `compute/hyperv` directly
loses that forward.

### 7. Lease behavior

The ICS DHCP server leases by MAC address, and Hyper-V keeps a VM's
dynamic MAC address for the life of the VM. On the bench, a guest kept
its lease across a VM restart and across the Talos install reboot.

The provider documents that the ICS network keeps its ID, prefix, and
isolation ID across a host reboot, and that a guest can get a
different lease after one. When a lease changes, the next apply
updates `connect_address` in place. On the bench, a worker that got a
new MAC address leased a new address. The next apply moved its Talos
API forward to the new address, and `talosctl` and `kubectl` reached
the node again.

Until that apply runs, the forwards point at the old address. A lease
change also changes the node's internal IP in Kubernetes. On the
bench, the worker re-registered with its new address. Operators SHOULD
run `windsor apply` after a host reboot.

An apply that updates a VM in place while that VM's addresses change
fails with "inconsistent result after apply"
(windsorcli/terraform-provider-hyperv#444). The apply after it
succeeds.

### 8. Upgrade from a NAT context

There is no in-place upgrade. To move a context from the NAT switch to
the ICS network, destroy it with `windsor destroy`, then run
`windsor bootstrap` again.

A single apply on a context that the NAT design made does not work:

- The ICS network and the NAT switch have the same name,
  `windsor-<context>`, and the same prefix. HNS rejects the ICS
  network while the switch exists (`0x803B0010`, a network with this
  name already exists).
- Terraform deletes the NAT switch before it moves the running VMs to
  the ICS network, and `Remove-VMSwitch` fails. The provider removes
  the `NetNat` first, then loses track of the switch
  (windsorcli/terraform-provider-hyperv#443).
- The Talos nodes are installed with the static network config. The
  compute step bakes the machine config only for the first boot, and
  `cluster/talos` skips the config apply. The nodes keep their static
  addresses after the switch changes.

If a single apply has already failed this way, run `windsor destroy`.
If the `windsor-<context>` VMSwitch stays on the host after the
destroy, remove it with `Remove-VMSwitch` before the next bootstrap.

## Consequences

- Guest addresses come from the host. Windsor does not need to know
  them before the VMs exist.
- Several contexts can share one host, because each has its own ICS
  network and isolation ID. Their listen ports MUST NOT collide.
- `cluster/talos` depends on the addresses that compute reports. A
  guest without the Hyper-V KVP daemon never reports an address, and
  VM creation fails after `guest_ipv4_timeout`. The Talos schematic
  includes `siderolabs/hyperv-guest-agent` for this reason.
- A lease change moves the forwards only on the next apply. Until
  then, the forwards point at the old address.
- `core` needs a `windsorcli/hyperv` release that has
  `hyperv_ics_network`, `hyperv_port_proxy`, and
  `wait_for_guest_ip_timeout`.
- The External-switch path (`hyperv.net_adapter`) and the LAN DHCP
  path (`network.dhcp`) do not change. They also use
  `wait_for_guest_ip_timeout` in place of the `time_sleep` wait.

## Alternatives considered

- Keep `NetNat` and add a DHCP server in a guest. This adds a VM to
  operate and does not remove the one-`NetNat`-per-host limit.
- Keep `NetNat` and point `hyperv_nat_static_mapping` at reported DHCP
  addresses. `NetNat` has no DHCP server, so the guests have no lease
  to report.
- Use the Hyper-V `Default Switch`. Its prefix changes at each host
  reboot and Windsor cannot set it.

## References

- windsorcli/terraform-provider-hyperv#423: provider design
- windsorcli/terraform-provider-hyperv#436: guest IP wait
- windsorcli/terraform-provider-hyperv#438: `hyperv_port_proxy`
- windsorcli/terraform-provider-hyperv#441: disabled firewall rule fix
- windsorcli/terraform-provider-hyperv#443: NAT switch delete with attached VMs
- windsorcli/terraform-provider-hyperv#444: `ip_addresses` on in-place VM update
- windsorcli/core#2757: several contexts on one Hyper-V host
- windsorcli/core#3199: `cluster.endpoint` with DHCP control planes
