---
title: DNS
description: DNS records for gateway hostnames, from a public cloud zone, a private cloud zone, or in-cluster CoreDNS, written by external-dns.
sidebar_order: 4
---

An `HTTPRoute` for `my-app.example.com` on the [gateway](../gateway/index.md) serves nothing until a DNS record points that name at the gateway's address. Core writes those records with *external-dns*, a controller that watches routes and publishes a record for each hostname. The records land in a *zone*, the set of records a DNS service answers for under one domain. A *public zone* lives in your cloud provider's DNS service and anyone can resolve it. A *private zone* resolves only inside your network, either attached to your cloud network or served by CoreDNS in the cluster.

The running example in this category gives `my-app` a public hostname under `example.com` and a private one under `int.example.com`. It sets both domains in a context's `values.yaml`:

```yaml
dns:
  public_domain: example.com
  private_domain: int.example.com
```

`dns.public_domain` makes Core create a [public zone](public.md) on AWS, Azure, GCP, or Hetzner, run external-dns against it, and provision the `external` gateway. The same key turns on [ACME certificates](../pki/acme.md). Setting [`dns.public_zone`](public.md#use-a-domain-without-a-zone) to `false` keeps `dns.public_domain` as a hostname and skips the zone, external-dns, and the DNS-01 identity. `dns.private_domain` provisions the `internal` gateway and its [private zone](private.md). `dns.private.driver` picks the server for that zone: a cloud private zone attached to your network on AWS, Azure, and GCP, and CoreDNS in the cluster elsewhere, as [Where the zone lives](private.md#where-the-zone-lives) describes.

## Domains and gateways

Each domain provisions one [gateway](../gateway/index.md): `external` for `dns.public_domain` and `internal` for `dns.private_domain`. The two domains MUST differ, and Windsor rejects a configuration where they match.

The private domain SHOULD be a subdomain of the public one, as `int.example.com` is of `example.com`. Each name then belongs to exactly one zone, so no client needs split-horizon DNS to get the right answer. The subdomain also lets the `internal` gateway use Let's Encrypt where Core writes the public zone: the DNS-01 challenge for `int.example.com` goes into the public `example.com` zone, and clients need no private root. [ACME](../pki/acme.md#internal-gateway) covers that case. Any other domain works too, and the `internal` gateway then takes its certificate from the [cluster CA](../pki/private-ca.md) unless the site supplies one.

Nothing defaults `dns.public_domain`. Core creates a public zone only when you set it, and only on AWS, Azure, GCP, or Hetzner. `dns.private_domain` has defaults on some platforms. Outside dev mode, Hyper-V, vSphere, and Proxmox default it to `<id>.local`. `dns.domain` is deprecated, and Windsor reads it only as a fallback for `dns.private_domain`.

> [!NOTE]
> Dev mode defaults `dns.private_domain` to `test`.

## What external-dns publishes

external-dns runs one instance per zone, `external-dns-public` and `external-dns-private`, and limits each to its own domain. Each instance reads `HTTPRoute` and `Ingress` resources and gives each hostname an `A` or `CNAME` record pointing at the gateway the route attaches to. The [`my-app` route](../gateway/index.md#hostnames) attaches to `external`, so `external-dns-public` publishes `my-app.example.com`. With the Envoy driver it also publishes the apex and a wildcard record for each gateway's domain, so an unrouted hostname reaches the catch-all `404`.

In a cloud zone, external-dns marks the records it owns with TXT records that carry the context `id`. It deletes a record when its route goes away and leaves records it does not own alone. On AWS each instance is also pinned to its zone's ID. Both instances run in `system-dns` and share one ServiceAccount, so one cloud identity covers both.

A Kyverno policy sets a 300-second TTL on routes in `system-*` namespaces and in namespaces labeled `policy.windsorcli.dev/managed: "true"`. A route that sets `external-dns.alpha.kubernetes.io/ttl` itself keeps its own value.

## Requirements

Windsor rejects these combinations when it validates the configuration:

- `dns.private.driver: coredns` and `dns.private.driver: cloud` need `dns.private_domain`.
- `dns.private.driver: cloud` is rejected outside AWS, Azure, and GCP.
- Outside workstation contexts, `dns.private.driver: coredns` needs a `LoadBalancer` `internal` gateway, since a node port cannot serve port 53.
- `dns.public_domain` and `dns.private_domain` are rejected when they match.
- `dns.private_domain` is rejected on Hetzner outside dev mode, since Hetzner gets no `internal` gateway.
- On AWS, Azure, GCP, and Hetzner, `email`, the ACME account contact, is required whenever a gateway uses Let's Encrypt.

## Configuration

The DNS keys and their defaults are listed below.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.public_domain` | string | none | Public zone to create, and the domain for ACME certificates. |
| `dns.public_zone` | boolean | `true` | Create the public zone, external-dns, and the DNS-01 identity for `dns.public_domain`. |
| `dns.private_domain` | string | `test` in dev, `<id>.local` on Hyper-V, vSphere, and Proxmox | Domain for the `internal` gateway. SHOULD be a subdomain of `dns.public_domain`. |
| `dns.private.driver` | string | by platform | `cloud`, `coredns`, or `none`. See [Where the zone lives](private.md#where-the-zone-lives). |
| `dns.private.enabled` | boolean | none | Deprecated. `true` acts as `dns.private.driver: coredns`. |
| `policies.external_dns_ttl` | string | `enabled` | `disabled` turns off the default TTL policy. |

## Reference

- [kustomize/dns](../../../kustomize/dns)
- [kustomize/gateway](../../../kustomize/gateway)
- [terraform/dns/zone](../../../terraform/dns/zone)
