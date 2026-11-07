---
title: CNI
description: Pod networking with Cilium on Talos clusters, Flannel where Cilium cannot run, and the managed CNI on EKS, AKS, and GKE.
sidebar_order: 6
---

A pod in the `my-app` namespace has no network until a plugin gives it one. That plugin is the *CNI* (Container Network Interface). The CNI assigns pod addresses and routes traffic between nodes. All other networking in the core blueprint runs on top of the CNI, from `LoadBalancer` addresses to the [gateway](../gateway/index.md) that serves `my-app.example.com`.

On Talos clusters, Core installs [Cilium](cilium.md). Cilium also replaces *kube-proxy*, the Kubernetes component that routes Service traffic. Cilium announces load balancer addresses, and it can run the [gateway](../gateway/cilium.md). [Flannel](flannel.md) is the CNI built into Talos, and it is the alternative where Cilium does not fit.

`cluster.cni.driver` in `values.yaml` selects the CNI. This example selects Cilium:

```yaml
cluster:
  cni:
    driver: cilium   # cilium or flannel
```

This table shows what Core does for each driver.

| `cluster.cni.driver` | What Core does |
|---|---|
| [`cilium`](cilium.md) | Disables the Talos Flannel and kube-proxy. Installs Cilium with Terraform, then gives it to Flux. |
| [`flannel`](flannel.md) | Installs nothing. The Talos Flannel and kube-proxy stay in place. |

## Defaults

Most clusters do not set `cluster.cni.driver`. Core selects a driver from the platform. This table gives the default for each type of cluster.

| Cluster | `cluster.cni.driver` default |
|---|---|
| Talos on docker-desktop | `flannel` |
| Talos on Incus with Colima | `flannel` |
| Talos on Hyper-V | `flannel` |
| Any other Talos cluster | `cilium` |
| EKS, AKS, and GKE | Not set. The managed CNI of the cloud runs, and Core installs no CNI. |

On Talos, a value that you set for `cluster.cni.driver` replaces the default.

> [!IMPORTANT]
> Set `cluster.cni.driver` before the first apply. The value changes the Talos machine config.

The Cilium add-on is for Talos. EKS accepts the same setting, but nobody tests that path. AKS and GKE keep their managed CNIs. GKE Dataplane V2 is already a managed Cilium from Google.

## What depends on the driver

The driver controls more than pod networking. For example, `my-app` can expose a `LoadBalancer` Service. With Cilium, Cilium assigns and announces the address. With Flannel, a separate load balancer does this, kube-vip by default. This table shows the other areas that change with the driver.

| Area | With `cilium` | With `flannel` |
|---|---|---|
| Service routing | Cilium replaces kube-proxy. | kube-proxy runs. |
| LoadBalancer addresses | Cilium LB IPAM assigns the addresses and announces them over L2. | kube-vip on metal, vSphere, Hyper-V, Incus, and Proxmox. MetalLB with `network.loadbalancer_driver: metallb`. See [Load balancing](../load-balancing.md). |
| Default [gateway](../gateway/index.md) driver | `cilium` | `envoy` |
| NetworkPolicy | Cilium enforces it. | Flannel does not enforce it. |
| Pod traffic encryption | WireGuard between nodes. On by default outside workstation contexts. | Not available. |
| Observability | Hubble, Cilium metrics, and Cilium and Hubble dashboards. | Not installed. |

With Cilium, three add-ons wait until the Cilium install is complete:

- The Cilium gateway waits, so that its Service gets an address.
- Private DNS waits when the gateway driver is `cilium`.
- The CSI storage driver waits. If it starts while Cilium loads its eBPF programs, it can crash-loop.

## Configuration

This table gives all the CNI keys in `values.yaml`. The vendor pages explain each key.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cluster.cni.driver` | string | by cluster | `cilium` or `flannel`. |
| `cluster.cni.encryption` | boolean | `true` outside workstation contexts | WireGuard between nodes on Cilium. |
| `network.loadbalancer_driver` | string | `cilium` with Cilium, `kube-vip` otherwise | `cilium`, `kube-vip`, `metallb`, or `none`. A Cilium cluster accepts only `cilium` or `none`. |
| `network.loadbalancer_ips.start` | string | none outside workstation contexts | First address for `LoadBalancer` Services that do not pin an address. |
| `network.loadbalancer_ips.end` | string | none outside workstation contexts | Last address of that range. |
| `topology` | string | derived | `single-node` runs one Cilium operator. All other values run two. |
| `telemetry.metrics.enabled` | boolean | `true` | Prometheus scrapes the Cilium and Hubble metrics. |

## Reference

- [kustomize/cni](../../../kustomize/cni)
- [terraform/cni/cilium](../../../terraform/cni/cilium)
- [kustomize/lb](../../../kustomize/lb)
- [kustomize/gateway](../../../kustomize/gateway)
