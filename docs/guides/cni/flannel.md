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

Flannel has no load balancer of its own. On metal, vSphere, Hyper-V, Incus, and Proxmox, Core runs kube-vip, which announces each [gateway](../gateway/index.md#service-exposure) at its `gateway.<name>.ip`. A `LoadBalancer` Service for `my-app` that pins no address needs a range to draw from, as in this example.

```yaml
network:
  loadbalancer_ips:
    start: 10.5.1.20
    end: 10.5.1.40
```

With the range set, Core adds the kube-vip cloud provider, which hands out its addresses. Without it, each Service MUST pin its own address with the `kube-vip.io/loadbalancerIPs` annotation. `network.loadbalancer_driver: metallb` swaps kube-vip for MetalLB, which requires the range. Gateway addresses MUST sit outside it.

> [!NOTE]
> docker-desktop has no routable node network. It skips the load balancer and exposes the gateway on a node port, as described under [Service exposure](../gateway/index.md#service-exposure).

## Gateway

With Flannel the gateway driver defaults to [`envoy`](../gateway/envoy.md). The [Cilium gateway](../gateway/cilium.md) needs Cilium as the CNI.

## Reference

Core installs no Kustomize components for this driver. The load balancer add-on is the only related wiring.

- [kustomize/lb](../../../kustomize/lb)
