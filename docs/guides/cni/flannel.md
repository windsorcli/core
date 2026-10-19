---
title: Flannel
description: Talos's built-in Flannel CNI, used where Cilium cannot run. Core installs nothing for it.
---

Flannel is Talos's built-in [CNI](index.md). With `cluster.cni.driver: flannel`, Core installs no CNI add-on and leaves Flannel and kube-proxy as Talos configured them. The [CNI overview](index.md) defines the terms this page assumes.

## Turn it on

Flannel is already the default on three Talos platforms, explained below and listed under [Defaults](index.md#defaults). Any other Talos cluster can opt in with this `values.yaml`.

```yaml
cluster:
  cni:
    driver: flannel
```

docker-desktop defaults to Flannel because Cilium cannot bootstrap through the localhost tunnel that reaches the API server. Incus with Colima also uses it, with kube-vip, because that platform tests storage drivers and Cilium's eBPF would skew the results. Hyper-V defaults to it as well.

## Load balancer addresses

Flannel has no load balancer of its own, so a `LoadBalancer` Service for `my-app` gets no address until you add one. You pick it with `network.loadbalancer_driver` and give it a pool, as in this example using MetalLB.

```yaml
network:
  loadbalancer_driver: metallb   # or kube-vip
  loadbalancer_ips:
    start: 10.5.1.10
    end: 10.5.1.30
```

The `loadbalancer_driver` key accepts `metallb` or `kube-vip`, and `loadbalancer_ips` sets the range that driver hands out.

> [!NOTE]
> docker-desktop has no routable node network. It skips the load balancer and exposes the gateway on a node port, as described under [Service exposure](../gateway/index.md#service-exposure).

## Gateway

With Flannel the gateway driver defaults to [`envoy`](../gateway/envoy.md). The [Cilium gateway](../gateway/cilium.md) needs Cilium as the CNI.

## Reference

Core installs no Kustomize components for this driver. The load balancer add-on is the only related wiring.

- [kustomize/lb](../../../kustomize/lb)
