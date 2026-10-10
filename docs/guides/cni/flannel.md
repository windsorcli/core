---
title: Flannel
description: Talos's built-in Flannel CNI, used where Cilium cannot run. Core installs nothing for it.
---

Flannel is Talos's built-in CNI. With `cluster.cni.driver: flannel`, Core installs no CNI add-on and leaves Flannel and kube-proxy as Talos configured them.

## Turn it on

```yaml
cluster:
  cni:
    driver: flannel
```

docker-desktop defaults to Flannel because Cilium cannot bootstrap through the localhost tunnel that reaches the API server. Incus with Colima, which exists to test storage drivers, uses it with kube-vip because Cilium's eBPF skews the results. Any other Talos cluster can opt in with the setting above.

## Load balancer addresses

Flannel has no load balancer of its own. To give `LoadBalancer` Services an address, set a driver:

```yaml
network:
  loadbalancer_driver: metallb   # or kube-vip
  loadbalancer_ips:
    start: 10.5.1.10
    end: 10.5.1.30
```

docker-desktop has no routable node network. It skips the load balancer and exposes the gateway on a node port, as described under [Service exposure](../gateway/index.md#service-exposure).

## Gateway

With Flannel the gateway driver defaults to [`envoy`](../gateway/envoy.md). The [Cilium gateway](../gateway/cilium.md) needs Cilium as the CNI.

## Reference

Core installs no Kustomize components for this driver. The load balancer add-on is the only related wiring.

- [kustomize/lb](../../../kustomize/lb)
