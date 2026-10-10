---
title: DNS
description: DNS records for gateway hostnames, from a public cloud zone, a private cloud zone, or in-cluster CoreDNS, written by external-dns.
sidebar_order: 4
---

Every hostname on the [gateway](../gateway/index.md) gets a DNS record from external-dns, which watches the Gateway and its `HTTPRoute` resources. The zone you configure decides where the records go: a [public zone](public.md) at your cloud provider for internet-facing names, or [CoreDNS](private.md) in the cluster for a private one. The following config can be placed in a context's `values.yaml` file to set either.

```yaml
dns:
  public_domain: example.com       # public zone at the cloud provider
  private_domain: internal.test    # private zone
  private:
    enabled: true                  # serve the private zone from CoreDNS
```

| Setting | What Core does |
|---|---|
| [`dns.public_domain`](public.md) | Creates a public zone on AWS, Azure, GCP, or Hetzner, runs external-dns against it, and provisions the `external` gateway. Also turns on [ACME certificates](../pki/acme.md). |
| [`dns.public_zone`](public.md#use-a-domain-without-a-zone) | When `false`, keeps `dns.public_domain` as a hostname and skips the zone, external-dns, and the DNS-01 identity. |
| [`dns.private_domain`](public.md#private-zones) | Provisions the `internal` gateway. On AWS, Azure, and GCP, records go to a private zone attached to your VPC or network. |
| [`dns.private.enabled`](private.md) | Runs CoreDNS in the cluster and points external-dns at it. |

## Domains and gateways

Each domain provisions one [gateway](../gateway/index.md): `external` for `dns.public_domain` and `internal` for `dns.private_domain`. Hostnames on a gateway are built from that gateway's own domain. The two domains MUST differ. Dev mode defaults `dns.private_domain` to `test` and turns `dns.private.enabled` on. `dns.domain` is deprecated and only serves as a fallback for `dns.private_domain`.

Only an explicit `dns.public_domain` creates a public zone, so a local cluster never starts a public zone or public certificate requests.

## What external-dns publishes

external-dns runs one instance per zone, `external-dns-public` and `external-dns-private`, each limited to its own domain. Each hostname on an attached `HTTPRoute` gets an `A` or `CNAME` record pointing at the address of the gateway it attaches to. external-dns marks the records it creates with TXT records that carry the context id, and it leaves the rest of the zone alone. On the Envoy driver it also publishes, for each gateway's own zone, the apex and a wildcard record. An unrouted hostname then reaches the catch-all `404`.

Both instances run in `system-dns` and share one ServiceAccount, so the cloud identity covers both. An instance exists only when its zone does.

## Requirements

Windsor rejects these combinations when it validates the configuration:

- `dns.private.enabled` needs `dns.private_domain`.
- `dns.private_domain` is rejected on Hetzner outside dev mode, since Hetzner has no private DNS.
- `dns.public_domain` needs `email`, the ACME account contact, unless `pki.public_issuer` is `selfsigned` or `dns.public_zone` is `false`.
- `pki.public_issuer: acme` is rejected with `dns.public_zone: false`.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.public_domain` | string | none | Public zone to create, and the domain for ACME certificates. |
| `dns.public_zone` | boolean | `true` | Create the public zone, external-dns, and the DNS-01 identity for `dns.public_domain`. |
| `dns.private_domain` | string | `test` in dev | Domain for the `internal` gateway: the CoreDNS zone, or the VPC-attached private zone. |
| `dns.private.enabled` | boolean | `true` in dev | Run CoreDNS for the private zone. |

## Reference

- [kustomize/dns](../../../kustomize/dns)
- [kustomize/gateway](../../../kustomize/gateway)
- [terraform/dns/zone](../../../terraform/dns/zone)
