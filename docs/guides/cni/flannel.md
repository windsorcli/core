---
title: Flannel
description: The Flannel CNI built into Talos, used where Cilium cannot run. Core installs nothing for it.
---

Flannel is the [CNI](index.md) built into Talos. With `cluster.cni.driver: flannel`, Core installs no CNI add-on. Flannel and kube-proxy stay as Talos configures them. The [CNI overview](index.md) defines the terms that this page uses.

## Turn it on

Flannel is the default on three Talos platforms. [Defaults](index.md#defaults) lists them. Other Talos clusters can select Flannel with this `values.yaml`:

```yaml
cluster:
  cni:
    driver: flannel
```

On docker-desktop, Cilium cannot bootstrap through the localhost tunnel to the API server. Incus with Colima tests storage drivers, and Cilium eBPF changes the results. That platform uses Flannel with kube-vip. Hyper-V also defaults to Flannel.

## Load balancer addresses

Flannel has no load balancer. On metal, vSphere, Hyper-V, Incus, and Proxmox, Core runs kube-vip. kube-vip announces each [gateway](../gateway/index.md#service-exposure) at its `gateway.<name>.ip`. A `LoadBalancer` Service for `my-app` that does not pin an address needs a range. This example sets a range:

```yaml
network:
  loadbalancer_ips:
    start: 10.5.1.20
    end: 10.5.1.40
```

When you set the range, Core adds the kube-vip cloud provider, which assigns addresses from it. Without the range, each Service MUST pin its address with the `kube-vip.io/loadbalancerIPs` annotation. Gateway addresses MUST be outside the range.

`network.loadbalancer_driver: metallb` replaces kube-vip with MetalLB. MetalLB requires the range. [Load balancing](../load-balancing.md) covers both drivers.

> [!NOTE]
> docker-desktop has no routable node network. It runs no load balancer, and it exposes the gateway on a node port. See [Service exposure](../gateway/index.md#service-exposure).

## Gateway

With Flannel, the gateway driver defaults to [`envoy`](../gateway/envoy.md). The [Cilium gateway](../gateway/cilium.md) needs Cilium as the CNI.

## Reference

Core installs no Kustomize components for this driver. The load balancer add-on is the only related wiring.

- [kustomize/lb](../../../kustomize/lb)
