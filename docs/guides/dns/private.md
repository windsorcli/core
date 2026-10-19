---
title: Private zones
description: Private DNS for the internal gateway, from a cloud private zone attached to the network or from CoreDNS in the cluster, chosen with dns.private.driver.
---

Grafana, the Flux web UI, and your own internal services sit on the `internal` gateway, and their names belong only on your own network. `dns.private_domain` gives the `internal` gateway its hostnames, such as `my-app.example.internal`, and external-dns publishes them to a [private zone](index.md). `dns.private.driver` decides where that zone lives.

## Drivers

The driver picks between a cloud private zone, CoreDNS in the cluster, or no private zone at all. Each driver that creates a zone runs one external-dns instance for it. The table below lists what each driver creates and the platforms that default to it.

| `dns.private.driver` | Private zone | Default on |
|---|---|---|
| `cloud` | A zone in the cloud's DNS service, attached to the VPC or virtual network. | AWS, Azure, and GCP. |
| `coredns` | CoreDNS in the cluster, serving the zone from etcd. | Every other platform, when `dns.private_domain` is set. |
| `none` | No private zone, and no external-dns instance for it. | Hetzner. |

`cloud` is rejected outside AWS, Azure, and GCP.

## Cloud private zones

On a cloud platform, the private zone belongs in the same network as the cluster. This `values.yaml` puts `example.internal` in a cloud private zone:

```yaml
dns:
  private_domain: example.internal
  private:
    driver: cloud
```

The network Terraform component creates the zone and attaches it to the VPC or virtual network, so only hosts on that network can resolve the names. The `internal` gateway never publishes to the public zone. Each cloud uses its own private zone service and external-dns provider, listed below.

| `platform` | Zone | external-dns provider |
|---|---|---|
| `aws` | Route53 private hosted zone | `route53` |
| `azure` | Azure Private DNS zone | `azure-private-dns` |
| `gcp` | Cloud DNS private zone | `google` |

## CoreDNS

A platform with no cloud DNS service, such as a local cluster or metal, still needs something to answer for `example.internal`. The `coredns` driver runs that DNS server inside the cluster:

```yaml
dns:
  private_domain: example.internal
  private:
    driver: coredns
```

Core installs CoreDNS and an etcd StatefulSet in `system-dns`. external-dns writes a record into etcd for each route, and CoreDNS answers from those records. When `dns.public_domain` is also set, CoreDNS answers for it too, so the cluster resolves public hostnames to its own gateway addresses. A local dev cluster uses this driver with the domain `test`.

> [!NOTE]
> external-dns only adds and updates records in CoreDNS. A record stays after its route is deleted.

CoreDNS and external-dns reach etcd over mutual TLS, with certificates from the `private` [cluster issuer](../pki/index.md). With `topology: ha`, CoreDNS runs two replicas on separate nodes.

The diagram below traces a query from a resolver to CoreDNS and a record from a route into etcd.

```mermaid
flowchart LR
  resolver[Workstation or LAN resolver]

  subgraph cluster[Kubernetes cluster]
    routes[HTTPRoutes]
    issuer[ClusterIssuer private]
    gw[Gateway address, port 53]

    subgraph systemdns[system-dns]
      edns[external-dns<br/>coredns provider]
      coredns[CoreDNS]
      etcd[etcd StatefulSet]
    end
  end

  routes -->|watched by| edns
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

### Reach it

CoreDNS serves port 53 at the `internal` gateway's address. How that port gets exposed depends on the gateway driver, as the table below shows.

| `gateway.driver` | Port 53 exposed through |
|---|---|
| [`envoy`](../gateway/envoy.md#private-dns) | UDP and TCP routes on the `internal` Gateway. On NodePort clusters, node port `30053`. |
| [`cilium`](../gateway/cilium.md#private-dns) | A `LoadBalancer` Service that shares the `internal` gateway's address through LB IPAM. |

On a local cluster, the workstation's DNS container forwards the private domain, and the public domain when set, to that address. On metal the address is routable on the LAN. Clients can query it directly, or an upstream resolver can forward `*.<dns.private_domain>` to it.

## Reference

- [terraform/network](../../../terraform/network)
- [kustomize/dns](../../../kustomize/dns)
- [kustomize/gateway](../../../kustomize/gateway)
- [kustomize/pki](../../../kustomize/pki)
