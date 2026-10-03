---
title: CNI
description: Pod networking with Cilium on Talos clusters, Flannel where Cilium cannot run, and the managed CNI on EKS, AKS, and GKE.
sidebar_order: 6
---

The CNI gives pods their network. On Talos clusters the core blueprint installs [Cilium](cilium.md), which also replaces kube-proxy, announces load balancer addresses, and can serve as the [gateway](../gateway/cilium.md). [Flannel](flannel.md) is the alternative where Cilium does not fit. The following config can be placed in a context's `values.yaml` file to choose.

```yaml
cluster:
  cni:
    driver: cilium   # cilium or flannel
```

| `cluster.cni.driver` | What Core does |
|---|---|
| [`cilium`](cilium.md) | Disables Talos's built-in Flannel and kube-proxy, installs Cilium with Terraform, and hands it to Flux. |
| [`flannel`](flannel.md) | Installs nothing. Talos's built-in Flannel and kube-proxy stay in place. |

## Defaults

| Cluster | `cluster.cni.driver` default |
|---|---|
| Talos on docker-desktop | `flannel` |
| Talos on Incus with Colima | `flannel` |
| Any other Talos cluster | `cilium` |
| EKS, AKS, and GKE | Not set. The cloud's managed CNI runs, and Core installs none. |

An explicit `cluster.cni.driver` wins on Talos. Because the driver changes the Talos machine config, set it before the first apply. The Cilium add-on is built for Talos. EKS can opt in with the same setting, but that path is untested. AKS and GKE keep their managed CNIs, and GKE's Dataplane V2 is already Google's managed Cilium.

## What depends on the driver

| Area | With `cilium` | With `flannel` |
|---|---|---|
| Service routing | Cilium replaces kube-proxy. | kube-proxy runs. |
| LoadBalancer addresses | Cilium announces them over L2 from `network.loadbalancer_ips`, with no extra controller. | Needs MetalLB or kube-vip, set with `network.loadbalancer_driver`. See [kustomize/lb](../../../kustomize/lb). |
| Default [gateway](../gateway/index.md) driver | `cilium` | `envoy` |
| NetworkPolicy | Cilium enforces it. | Flannel does not enforce it. |
| Observability | Hubble, Cilium metrics, and a Cilium dashboard. | Not installed. |

Two add-ons wait for the Cilium install. The Cilium gateway waits so its Service gets an address, and the CSI storage driver waits because it can crash-loop if it starts while Cilium's eBPF programs are still loading.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cluster.cni.driver` | string | by cluster | `cilium` or `flannel`. |
| `network.loadbalancer_ips.start` | string | derived | First address of the load balancer pool. |
| `network.loadbalancer_ips.end` | string | derived | Last address of the load balancer pool. |
| `network.loadbalancer_driver` | string | none | `metallb`, `kube-vip`, or `none`. Used with Flannel. Ignored with Cilium. |
| `topology` | string | derived | `single-node` runs one Cilium operator. Everything else runs two. |
| `telemetry.metrics.enabled` | boolean | `true` | Scrape Cilium and Hubble metrics with Prometheus. |

## Reference

- [kustomize/cni](../../../kustomize/cni)
- [terraform/cni/cilium](../../../terraform/cni/cilium)
- [kustomize/lb](../../../kustomize/lb)
- [kustomize/gateway](../../../kustomize/gateway)
