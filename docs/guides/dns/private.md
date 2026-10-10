---
title: Private zones
description: In-cluster CoreDNS serving a private zone, so workstations and LANs resolve gateway hostnames without a cloud DNS zone.
---

Local clusters and metal have no cloud zone to write to, so Core runs CoreDNS in the cluster as the authoritative server for one domain.

## Turn it on

```yaml
dns:
  private_domain: internal.test
  private:
    enabled: true
```

Core installs CoreDNS and an etcd StatefulSet in `system-dns` and points external-dns at them. external-dns writes records into etcd as routes appear, and CoreDNS answers for everything under `dns.private_domain` from those records. With `dns.public_domain` also set, it answers for that domain too, so a local or metal cluster resolves public hostnames to its own gateway addresses. Both reach etcd over mutual TLS, with certificates from the `private` [cluster issuer](../pki/index.md). With `topology: ha`, CoreDNS runs several replicas. Dev mode turns all of this on with the domain `test`. `dns.private.enabled` needs `dns.private_domain`.

## Reach it

CoreDNS listens on port 53, and the gateway driver determines how clients reach it. Port 53 is a utility surface, so it binds to the `internal` gateway only.

| `gateway.driver` | Port 53 exposed through |
|---|---|
| [`envoy`](../gateway/envoy.md#private-dns) | UDP and TCP routes on the `internal` Gateway. On NodePort clusters, node port `30053`. |
| [`cilium`](../gateway/cilium.md#private-dns) | A `LoadBalancer` Service that shares the gateway address through LB IPAM. |

The address must fall inside `network.loadbalancer_ips`. On a local cluster, the workstation's stub resolver forwards the private domain to it. On metal the address is routable on the LAN. LAN clients can query it directly, or an upstream resolver can forward `*.<dns.private_domain>` to it.

## Under the hood

```mermaid
flowchart LR
  routes[HTTPRoutes]
  resolver[Workstation or LAN resolver]

  subgraph systemdns[system-dns]
    edns[external-dns<br/>coredns provider]
    coredns[CoreDNS]
    etcd[etcd StatefulSet]
  end

  issuer[ClusterIssuer private]
  gw[Gateway address, port 53]

  edns -->|watches| routes
  edns -->|writes records| etcd
  coredns -->|reads| etcd
  issuer -->|etcd TLS| etcd
  resolver -->|queries| gw
  gw --> coredns
  classDef app fill:#2E7D3233,stroke:#2E7D32
  classDef store fill:#F57C0033,stroke:#F57C00
  classDef k8s fill:#326CE533,stroke:#326CE5
  class routes,resolver app
  class etcd store
  class edns,coredns,issuer,gw k8s
```

## Reference

- [kustomize/dns](../../../kustomize/dns)
- [kustomize/gateway](../../../kustomize/gateway)
- [kustomize/pki](../../../kustomize/pki)
