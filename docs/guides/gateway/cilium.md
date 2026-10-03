---
title: Cilium Gateway
description: Cilium's Gateway API controller as the cluster gateway driver, served by the Envoy that Cilium runs on every node.
---

The `cilium` driver uses the Gateway API controller built into Cilium, so it needs the [Cilium CNI](../cni/cilium.md) (`cluster.cni.driver: cilium`). The cilium-operator turns `Gateway` and `HTTPRoute` resources into Envoy configuration, and the `cilium-envoy` pod that Cilium runs on every node serves the traffic. Core installs no separate gateway controller or proxy Deployment. TLS ends in that Envoy, using a certificate from the `pki` add-on.

## Turn it on

```yaml
cluster:
  cni:
    driver: cilium   # The cilium cni must be enabled to use the gateway
gateway:
  driver: cilium
```

`gateway.driver` defaults to `cilium` when Cilium is the CNI and to [`envoy`](envoy.md) otherwise. AWS and docker-desktop always default to `envoy`. See [CNI defaults](../cni/index.md#defaults) for which clusters use Cilium.

Core creates a `cilium` GatewayClass and the `external` Gateway in `system-gateway`. The Cilium release belongs to the [CNI add-on](../cni/cilium.md), which turns on Gateway API support when this driver is selected. The Gateway API CRDs are applied before the Cilium operator starts.

## Addresses

Cilium's LB IPAM gives the Gateway's Service the first address in `network.loadbalancer_ips` and announces it over L2 from one node at a time. Cilium picks that node first come first serve, so announcement load can be uneven, and it does not work with `externalTrafficPolicy: Local`. The address is shareable across namespaces, so other Services can reuse it on different ports. The Gateway waits for the Cilium CNI install. That puts the sharing policy in place before the Service exists.

On Hetzner the cloud controller fills the Service instead, and the LB IPAM annotations are left off.

## Private DNS

`dns.private.enabled` gives CoreDNS its own `LoadBalancer` Service on port 53, which shares the gateway's address through LB IPAM. The zone itself is covered under [Private zones](../dns/private.md).

## What differs from Envoy

Both drivers run Envoy and implement the same Gateway API. [Envoy Gateway](envoy.md) manages dedicated Envoy proxies per Gateway through its own controller. Cilium shares one Envoy per node across all Gateways and exposes configuration through Gateway API and Cilium annotations.

Cilium has no catch-all `404`, no `EnvoyProxy` resource, and none of Envoy Gateway's route extensions such as `HTTPRouteFilter`. Prometheus scrapes the `cilium-envoy` pods, but Core ships no gateway dashboard or alerts for the Cilium driver. The Envoy driver ships both.

Choose Cilium when you want no extra controller, load balancer addresses without MetalLB or kube-vip, and CoreDNS sharing the gateway address. Choose Envoy Gateway when you want Envoy-specific extensions, a proxy per Gateway that scales on its own, or independence from the CNI.

## Reference

- [kustomize/gateway/install/cilium](../../../kustomize/gateway/install/cilium)
- [kustomize/gateway/resources/cilium](../../../kustomize/gateway/resources/cilium)
- [kustomize/cni](../../../kustomize/cni)
- [kustomize/crds](../../../kustomize/crds)
- [kustomize/pki](../../../kustomize/pki)
