---
title: CNI
description: Pod networking with Cilium on Talos clusters, Flannel where Cilium cannot run, and the managed CNI on EKS, AKS, and GKE.
sidebar_order: 6
---

A pod in namespace `my-app` can't reach another pod, or be reached by a Service, until something gives it a network. That something is the *CNI*, the Container Network Interface plugin that assigns pod addresses and routes traffic between nodes. Every other networking feature in the core blueprint, from `LoadBalancer` addresses to the [gateway](../gateway/index.md) that serves `my-app.example.com`, sits on top of it.

On Talos clusters the core blueprint installs [Cilium](cilium.md). Besides pod networking, Cilium replaces *kube-proxy*, the Kubernetes component that routes Service traffic, and it announces load balancer addresses and can serve as the [gateway](../gateway/cilium.md). [Flannel](flannel.md), Talos's built-in CNI, is the alternative where Cilium does not fit. You choose between them with `cluster.cni.driver` in a context's `values.yaml`, which this minimal example sets to Cilium.

```yaml
cluster:
  cni:
    driver: cilium   # cilium or flannel
```

The two values do very different amounts of work. This table summarizes what Core does for each.

| `cluster.cni.driver` | What Core does |
|---|---|
| [`cilium`](cilium.md) | Disables Talos's built-in Flannel and kube-proxy, installs Cilium with Terraform, and hands it to Flux. |
| [`flannel`](flannel.md) | Installs nothing. Talos's built-in Flannel and kube-proxy stay in place. |

## Defaults

Most clusters never set `cluster.cni.driver`, because Core picks a driver from the platform. Local and Hyper-V Talos clusters get Flannel, other Talos clusters get Cilium, and the managed clouds keep their own CNI. The defaults per cluster are listed here.

| Cluster | `cluster.cni.driver` default |
|---|---|
| Talos on docker-desktop | `flannel` |
| Talos on Incus with Colima | `flannel` |
| Talos on Hyper-V | `flannel` |
| Any other Talos cluster | `cilium` |
| EKS, AKS, and GKE | Not set. The cloud's managed CNI runs, and Core installs none. |

On Talos an explicit `cluster.cni.driver` overrides the default.

> [!IMPORTANT]
> Set `cluster.cni.driver` before the first apply. It changes the Talos machine config.

The Cilium add-on targets Talos. EKS can opt in with the same setting, but that path is untested. AKS and GKE keep their managed CNIs, and GKE's Dataplane V2 is already Google's managed Cilium.

## What depends on the driver

The driver decides more than pod networking. Suppose `my-app` exposes a `LoadBalancer` Service. With Cilium, Cilium itself assigns and announces the address. With Flannel, a separate load balancer does, kube-vip by default. The same split runs through service routing, the default gateway, policy enforcement, encryption, and observability, as this table shows.

| Area | With `cilium` | With `flannel` |
|---|---|---|
| Service routing | Cilium replaces kube-proxy. | kube-proxy runs. |
| LoadBalancer addresses | Cilium LB IPAM assigns them and announces them over L2, with no extra controller. | kube-vip on metal, vSphere, Hyper-V, Incus, and Proxmox, or MetalLB with `network.loadbalancer_driver: metallb`. See [kustomize/lb](../../../kustomize/lb). |
| Default [gateway](../gateway/index.md) driver | `cilium` | `envoy` |
| NetworkPolicy | Cilium enforces it. | Flannel does not enforce it. |
| Pod traffic encryption | Cilium supports WireGuard encryption between nodes. Core does not turn it on yet. | Not available. |
| Observability | Hubble, Cilium metrics, and Cilium and Hubble dashboards. | Not installed. |

With Cilium, three add-ons also wait for the Cilium install to finish. The Cilium gateway waits so its Service gets an address, and private DNS waits too when the gateway driver is `cilium`. The CSI storage driver waits because it can crash-loop if it starts while Cilium's eBPF programs are loading.

## Configuration

The keys below are the whole CNI surface in `values.yaml`. The vendor pages explain each in context.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cluster.cni.driver` | string | by cluster | `cilium` or `flannel`. |
| `network.loadbalancer_driver` | string | `cilium` with Cilium, `kube-vip` otherwise | `cilium`, `kube-vip`, `metallb`, or `none`. Cilium clusters accept only `cilium` or `none`. |
| `network.loadbalancer_ips.start` | string | none outside workstation contexts | First address for `LoadBalancer` Services that do not pin one. |
| `network.loadbalancer_ips.end` | string | none outside workstation contexts | Last address of that range. |
| `topology` | string | derived | `single-node` runs one Cilium operator. Everything else runs two. |
| `telemetry.metrics.enabled` | boolean | `true` | Scrape Cilium and Hubble metrics with Prometheus. |

## Reference

- [kustomize/cni](../../../kustomize/cni)
- [terraform/cni/cilium](../../../terraform/cni/cilium)
- [kustomize/lb](../../../kustomize/lb)
- [kustomize/gateway](../../../kustomize/gateway)
