---
title: Load balancing
description: Addresses for nodes, LoadBalancer Services, and the Kubernetes API on metal, vSphere, Hyper-V, Incus, and Proxmox, from DHCP or values.yaml, Cilium, kube-vip, MetalLB, and a Talos VIP.
sidebar_order: 7
---

On a cloud, a `LoadBalancer` Service gets an address from the load balancer of the provider. A cluster on metal, vSphere, Hyper-V, Incus, or Proxmox has no such provider. The address must come from the cluster, and the cluster must announce it on the site network.

The Kubernetes API has the same problem at a lower level. Clients need one address that answers while one or more control planes are up. Core solves both problems. Each address that Core uses is in `values.yaml`.

This `values.yaml` is for a vSphere cluster with three control planes on a plant VLAN. It shows each address:

```yaml
platform: vsphere
cluster:
  endpoint: https://10.20.0.5:6443
  vip: true
  controlplanes:
    count: 3
    nodes:
      controlplane-1:
        node: 10.20.0.11
      controlplane-2:
        node: 10.20.0.12
      controlplane-3:
        node: 10.20.0.13
gateway:
  internal:
    ip: 10.20.0.10
  external:
    ip: 10.30.0.20
network:
  loadbalancer_ips:
    start: 10.20.0.100
    end: 10.20.0.120
```

These keys set the addresses:

- `cluster.controlplanes.nodes` gives the address of each control plane. See [Node addresses](#node-addresses).
- `cluster.endpoint` is the address where clients connect to the API. `cluster.vip` makes Talos own that address.
- `gateway.<name>.ip` pins each [gateway](gateway/index.md#service-exposure) to its address.
- `network.loadbalancer_ips` is an optional range for other `LoadBalancer` Services.

## Node addresses

Each node needs an address on the site network. On Hyper-V, vSphere, Proxmox, and Incus, the address comes from DHCP or from `values.yaml`.

`network.dhcp: true` makes each node get its address from the DHCP server of the site. Compute reports the leased addresses, and talosctl uses them.

Without DHCP, each node MUST have an entry in `values.yaml`. The entry keys are the pool positions:

- `controlplane-1` to `controlplane-N` under `cluster.controlplanes.nodes`
- `worker-1` to `worker-N` under `cluster.workers.nodes`

`N` is the `count` of the pool. Windsor rejects a configuration with a missing entry. Workstation contexts on Incus are the exception, because Windsor makes their network. Hyper-V behind its NAT switch is also an exception.

### DHCP

A single control plane can serve the API at its leased address. With more than one control plane, no leased address is stable enough. Windsor then requires `cluster.endpoint`. The endpoint is a Talos VIP or an address that an external load balancer serves.

Core cannot check these rules, because it does not know the DHCP scope:

- A Talos VIP MUST be outside the DHCP scope. If it is not, the DHCP server can lease it to another host.
- Control planes SHOULD have DHCP reservations. When the address of a control plane changes, the control plane writes a new etcd peer address.

On Hyper-V and Proxmox, `mac_address` in a node entry sets a fixed MAC address on the guest NIC. Use it to make a DHCP reservation on the router before the VM exists. Without it, the hypervisor assigns a MAC address. This entry fixes the MAC address of the first control plane:

```yaml
network:
  dhcp: true
cluster:
  controlplanes:
    nodes:
      controlplane-1:
        mac_address: "02:00:00:00:00:11"
```

## Service load balancer

A *Service load balancer* assigns addresses to `LoadBalancer` Services. It answers ARP for these addresses, so that traffic for an address goes to a node that serves it. `network.loadbalancer_driver` selects the implementation. Core sets the default from the [CNI](cni/index.md). This table gives the drivers.

| `network.loadbalancer_driver` | Default with | Gateway addresses | `network.loadbalancer_ips` |
|---|---|---|---|
| `cilium` | The Cilium CNI | A pool block for each gateway IP, pinned through `lbipam.cilium.io/ips`. | Optional. Added to the pool. |
| `kube-vip` | All other CNIs | Pinned through `kube-vip.io/loadbalancerIPs`. | Optional. When set, Core adds the kube-vip cloud provider to assign addresses from the range. |
| `metallb` | none | A pool entry for each gateway IP, pinned through `metallb.io/loadBalancerIPs`. | Required. |
| `none` | none | No load balancer in the cluster. | Ignored. |

The driver runs by default in ARP mode on metal, vSphere, Hyper-V, Incus, and Proxmox. A Cilium cluster runs no second load balancer, so it accepts only `cilium` or `none`. When both gateways use `NodePort`, no gateway needs an address, and Core disables kube-vip and MetalLB.

Gateway addresses MUST be outside `network.loadbalancer_ips`. Windsor rejects a configuration where they overlap. Without the range, a Service that is not a gateway gets no address. The exception is a Service that pins its own address through the annotation of the driver.

## The API endpoint

Talos can hold the API address itself, as a *VIP* that the control planes share. Talos uses etcd to elect one control plane, which answers ARP for the VIP. When that node goes down, Talos moves the VIP to another control plane. Talos announces the VIP without a Kubernetes workload. The VIP thus answers during bootstrap, before Flux or a CNI runs.

`cluster.vip: true` enables the VIP for the host in `cluster.endpoint`. Core adds the VIP to the machine config of each control plane, and to the certificate SANs of the API server. The host MUST be an IPv4 address that no control plane uses. If it is not, the Talos Terraform component fails.

> [!IMPORTANT]
> All control planes MUST be on the same layer-2 segment as the VIP. ARP does not cross a router.

When `cluster.vip` is not set or is `false`, Core configures no VIP. `cluster.endpoint` is then the address of a control plane. It can also be an address that a load balancer of the site serves. Core never infers a VIP from the endpoint. If two systems claim the same address, both break.

The VIP serves only the Kubernetes API. talosctl uses the node addresses as its endpoints. Cilium connects to the API through [KubePrism](cni/cilium.md#bootstrap) on each node. `cluster.vip` works on Incus, Proxmox, vSphere, and Hyper-V. On Hyper-V with both gateways on `NodePort`, clients connect to the API through the address of the host, and `cluster.vip` does not apply.

## Configuration

This table gives the keys for node addresses, the load balancer, and the API endpoint.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `network.dhcp` | boolean | `false` | Nodes get their addresses from DHCP on Hyper-V, vSphere, Proxmox, and Incus. |
| `cluster.controlplanes.nodes.<controlplane-N>.node` | string | none | Address of a control plane. Required for each control plane without DHCP. |
| `cluster.workers.nodes.<worker-N>.node` | string | none | Address of a worker. Required for each worker without DHCP. |
| `cluster.<pool>.nodes.<name>.mac_address` | string | assigned by the hypervisor | Fixed MAC address of the guest NIC on Hyper-V and Proxmox. |
| `network.loadbalancer_driver` | string | `cilium` with Cilium, `kube-vip` otherwise | `cilium`, `kube-vip`, `metallb`, or `none`. |
| `network.loadbalancer_ips.start` | string | none outside workstation contexts | First address for `LoadBalancer` Services that do not pin an address. |
| `network.loadbalancer_ips.end` | string | none outside workstation contexts | Last address of that range. |
| `network.loadbalancer_mode` | string | none | Announcement mode. Only `arp` is supported. |
| `gateway.<name>.ip` | string | none | Address of a `LoadBalancer` gateway. See [Gateway](gateway/index.md#service-exposure). |
| `cluster.endpoint` | string | by platform | Kubernetes API endpoint, `https://host:port`. |
| `cluster.vip` | boolean | `false` | Makes the host in `cluster.endpoint` a Talos VIP. |

## Reference

- [kustomize/lb](../../kustomize/lb)
- [kustomize/cni](../../kustomize/cni)
- [terraform/cluster/talos](../../terraform/cluster/talos)
- [terraform/compute](../../terraform/compute)
