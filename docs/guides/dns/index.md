---
title: DNS
description: DNS records for gateway hostnames, from a public cloud zone, a private cloud zone, or in-cluster CoreDNS, written by external-dns.
sidebar_order: 4
---

An `HTTPRoute` for `my-app.example.com` on the [gateway](../gateway/index.md) serves nothing until a DNS record points that name at the gateway address. Core writes these records with *external-dns*. external-dns is a controller that watches routes and publishes a record for each hostname.

The records go into a *zone*. A zone is the set of records that a DNS service answers for under one domain. A *public zone* is in the DNS service of your cloud provider, and all clients can resolve it. A *private zone* resolves only in your network. It is attached to your cloud network, or CoreDNS serves it in the cluster.

The example in this category gives `my-app` a public hostname under `example.com` and a private hostname under `int.example.com`. This `values.yaml` sets both domains:

```yaml
dns:
  public_domain: example.com
  private_domain: int.example.com
```

`dns.public_domain` does these things:

- On AWS, Azure, GCP, or Hetzner, Core makes a [public zone](public.md) and runs external-dns for it.
- Core provisions the `external` gateway.
- Core enables [ACME certificates](../pki/acme.md) through that zone.

[`dns.public_zone: false`](public.md#use-a-domain-without-a-zone) keeps `dns.public_domain` as a hostname. Core then makes no zone, no external-dns, and no DNS-01 identity.

`dns.private_domain` provisions the `internal` gateway and its [private zone](private.md). `dns.private.driver` selects the server for that zone. On AWS, Azure, and GCP, the server is a cloud private zone attached to your network. On other platforms, it is CoreDNS in the cluster. See [Where the zone lives](private.md#where-the-zone-lives).

## Domains and gateways

Each domain provisions one [gateway](../gateway/index.md): `external` for `dns.public_domain` and `internal` for `dns.private_domain`. The two domains MUST be different. Windsor rejects a configuration where they are the same.

The private domain SHOULD be a subdomain of the public domain, as `int.example.com` is of `example.com`. Then each name belongs to one zone only, and no client needs split-horizon DNS.

The subdomain also lets the `internal` gateway use Let's Encrypt where Core writes the public zone. The DNS-01 challenge for `int.example.com` goes into the public `example.com` zone, and clients need no private root. [ACME](../pki/acme.md#internal-gateway) covers this case. Other domains also work. With another domain, the `internal` gateway gets its certificate from the [cluster CA](../pki/private-ca.md), unless the site supplies one.

`dns.public_domain` has no default. Core makes a public zone only when you set it, and only on AWS, Azure, GCP, or Hetzner. `dns.private_domain` has a default on some platforms. Outside dev mode, Hyper-V, vSphere, and Proxmox set it to `<id>.local`. `dns.domain` is deprecated. Windsor reads it only when `dns.private_domain` is not set.

> [!NOTE]
> Dev mode sets `dns.private_domain` to `test`.

## What external-dns publishes

external-dns runs one instance for each zone, `external-dns-public` and `external-dns-private`. Each instance is limited to its own domain. Each instance reads `HTTPRoute` and `Ingress` resources. It gives each hostname an `A` or `CNAME` record that points at the gateway of the route.

The [`my-app` route](../gateway/index.md#hostnames) attaches to `external`, so `external-dns-public` publishes `my-app.example.com`. With the Envoy driver, external-dns also publishes an apex record and a wildcard record for the domain of each gateway. A hostname without a route then gets the catch-all `404`.

In a cloud zone, external-dns marks the records that it owns with TXT records. These TXT records contain the context `id`. external-dns deletes a record when its route is removed. It does not change records that it does not own. On AWS, each instance is also pinned to the ID of its zone. Both instances run in `system-dns` with one ServiceAccount, so one cloud identity covers both.

A Kyverno policy sets a TTL of 300 seconds on routes in two types of namespace:

- `system-*` namespaces
- namespaces with the label `policy.windsorcli.dev/managed: "true"`

A route that sets `external-dns.alpha.kubernetes.io/ttl` keeps its own value.

## Requirements

Windsor rejects these configurations during validation:

- `dns.private.driver: coredns` or `dns.private.driver: cloud` without `dns.private_domain`.
- `dns.private.driver: cloud` outside AWS, Azure, and GCP.
- `dns.private.driver: coredns` without a `LoadBalancer` `internal` gateway, outside workstation contexts. A node port cannot serve port 53.
- `dns.public_domain` and `dns.private_domain` with the same value.
- `dns.private_domain` on Hetzner outside dev mode. Hetzner has no `internal` gateway.
- A gateway that uses Let's Encrypt on AWS, Azure, GCP, or Hetzner without `email`, the ACME account contact.

## Configuration

This table gives the DNS keys and their defaults.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.public_domain` | string | none | Public zone to make, and the domain for ACME certificates. |
| `dns.public_zone` | boolean | `true` | Makes the public zone, external-dns, and the DNS-01 identity for `dns.public_domain`. |
| `dns.private_domain` | string | `test` in dev, `<id>.local` on Hyper-V, vSphere, and Proxmox | Domain of the `internal` gateway. SHOULD be a subdomain of `dns.public_domain`. |
| `dns.private.driver` | string | by platform | `cloud`, `coredns`, or `none`. See [Where the zone lives](private.md#where-the-zone-lives). |
| `dns.private.enabled` | boolean | none | Deprecated. `true` has the same effect as `dns.private.driver: coredns`. |
| `policies.external_dns_ttl` | string | `enabled` | `disabled` turns off the default TTL policy. |

## Reference

- [kustomize/dns](../../../kustomize/dns)
- [kustomize/gateway](../../../kustomize/gateway)
- [terraform/dns/zone](../../../terraform/dns/zone)
