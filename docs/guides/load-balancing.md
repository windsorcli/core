---
title: Load balancing
description: Addresses for LoadBalancer Services and the Kubernetes API on metal, vSphere, Hyper-V, Incus, and Proxmox, from Cilium, kube-vip, MetalLB, and a Talos VIP.
sidebar_order: 7
---

On a cloud, a `LoadBalancer` Service gets an address from the provider's load balancer. A cluster on metal, vSphere, Hyper-V, Incus, or Proxmox has no such provider, so the address has to come from inside the cluster and be announced on the site network. The Kubernetes API has the same problem one level down: clients need one address that answers while any control plane is up. Core handles both, and every address it uses appears in `values.yaml`.

This `values.yaml` for a three-control-plane vSphere cluster on a plant VLAN shows each address:

```yaml
platform: vsphere
cluster:
  endpoint: https://10.20.0.5:6443
  vip: true
  controlplanes:
    count: 3
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

`cluster.endpoint` is where clients reach the API, and `cluster.vip` makes Talos own that address. `gateway.<name>.ip` pins each [gateway](gateway/index.md#service-exposure) to its address. `network.loadbalancer_ips` is an optional range for other `LoadBalancer` Services.

## Service load balancer

A *Service load balancer* assigns addresses to `LoadBalancer` Services and answers ARP for them, so traffic for an address reaches a node that serves it. `network.loadbalancer_driver` picks the implementation, and Core defaults it from the [CNI](cni/index.md). This table lists the drivers.

| `network.loadbalancer_driver` | Default with | Gateway addresses | `network.loadbalancer_ips` |
|---|---|---|---|
| `cilium` | The Cilium CNI | A pool block per gateway IP, pinned through `lbipam.cilium.io/ips`. | Optional. Appended to the pool. |
| `kube-vip` | Any other CNI | Pinned through `kube-vip.io/loadbalancerIPs`. | Optional. When set, Core adds the kube-vip cloud provider to hand out the range. |
| `metallb` | none | A pool entry per gateway IP, pinned through `metallb.io/loadBalancerIPs`. | Required. |
| `none` | none | No in-cluster load balancer. | Ignored. |

The driver runs by default on metal, vSphere, Hyper-V, Incus, and Proxmox, in ARP mode. A Cilium cluster runs no second load balancer, so it accepts only `cilium` or `none`. When both gateways use `NodePort`, no gateway needs an address and Core turns kube-vip and MetalLB off.

Gateway addresses MUST sit outside `network.loadbalancer_ips`, and Windsor rejects a configuration where they overlap. Without the range, a Service other than a gateway gets no address unless it pins its own through the driver's annotation.

## The API endpoint

Talos can hold the API address itself, as a *VIP* that the control planes share. Talos elects one control plane through etcd to answer ARP for it, and moves it when that node goes down. Talos announces it with no Kubernetes workload, so it answers during bootstrap, before Flux or any CNI runs.

`cluster.vip: true` turns this on for the host in `cluster.endpoint`. Core adds the VIP to every control plane's machine config and to the API server's certificate SANs. The host MUST be an IPv4 address that no control plane uses, and the Talos Terraform component fails otherwise.

> [!IMPORTANT]
> Every control plane MUST share one layer-2 segment with the VIP. ARP does not cross a router.

With `cluster.vip` unset or `false`, Core configures no VIP. `cluster.endpoint` is then a control-plane node's own address, or an address a load balancer the site already runs serves. Core never infers a VIP from the endpoint, because claiming an address another system owns breaks both.

The VIP serves the Kubernetes API only. talosctl keeps the node addresses as its endpoints, and Cilium reaches the API through [KubePrism](cni/cilium.md#bootstrap) on each node. `cluster.vip` works on Incus, Proxmox, vSphere, and Hyper-V. On Hyper-V with both gateways on `NodePort`, clients reach the API through the host's address, and `cluster.vip` does not apply.

## DHCP

On Hyper-V, vSphere, and Proxmox, `network.dhcp: true` lets every node take its address from the site's DHCP server. Compute reports the leased addresses, and talosctl targets them. A single control plane can serve the API at its leased address. With several, no leased address is stable enough, so Windsor requires `cluster.endpoint`, either a Talos VIP or an address an external load balancer serves.

Two rules apply that Core cannot check, because it does not know the DHCP scope:

- A Talos VIP MUST sit outside the DHCP scope. Otherwise the DHCP server can lease it to another host.
- Control planes SHOULD hold DHCP reservations. A control plane whose address changes rewrites its etcd peer address.

## Configuration

The keys below cover the load balancer and the API endpoint.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `network.loadbalancer_driver` | string | `cilium` with Cilium, `kube-vip` otherwise | `cilium`, `kube-vip`, `metallb`, or `none`. |
| `network.loadbalancer_ips.start` | string | none outside workstation contexts | First address for `LoadBalancer` Services that do not pin one. |
| `network.loadbalancer_ips.end` | string | none outside workstation contexts | Last address of that range. |
| `network.loadbalancer_mode` | string | none | Announcement mode. Only `arp` is supported. |
| `gateway.<name>.ip` | string | none | Address of a `LoadBalancer` gateway. See [Gateway](gateway/index.md#service-exposure). |
| `cluster.endpoint` | string | by platform | Kubernetes API endpoint, `https://host:port`. |
| `cluster.vip` | boolean | `false` | Make the host in `cluster.endpoint` a Talos VIP. |
| `network.dhcp` | boolean | `false` | Take node addresses from DHCP on Hyper-V, vSphere, and Proxmox. |

## Reference

- [kustomize/lb](../../kustomize/lb)
- [kustomize/cni](../../kustomize/cni)
- [terraform/cluster/talos](../../terraform/cluster/talos)
