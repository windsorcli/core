---
title: DNS
description: DNS records for gateway hostnames, from a public cloud zone through external-dns or a private zone served by in-cluster CoreDNS.
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
| [`dns.public_domain`](public.md) | Creates a public zone on AWS, Azure, GCP, or Hetzner and runs external-dns against it. Also turns on [ACME certificates](../pki/acme.md). |
| [`dns.private.enabled`](private.md) | Runs CoreDNS in the cluster and points external-dns at it. |
| `gateway.access: private` | Publishes to a private zone in your VPC or network. See [Private gateway zones](public.md#private-gateway-zones). |

## Which domain names the gateway

Hostnames are built from a single domain, the first one set of `dns.public_domain`, `dns.private_domain`, and `dns.domain`. A private gateway always uses `dns.private_domain`. Dev mode defaults `dns.domain` and `dns.private_domain` to `test` and turns `dns.private.enabled` on.

Only an explicit `dns.public_domain` creates a public zone. A domain set through `dns.domain` for local use never starts a public zone or public certificate requests.

## What external-dns publishes

Each hostname on an attached `HTTPRoute` gets an `A` or `CNAME` record pointing at the gateway address. external-dns marks the records it creates with TXT records that carry the context id, and it leaves the rest of the zone alone. On the Envoy driver, with a public domain or a private gateway, it also publishes the apex and a wildcard record. An unrouted hostname then reaches the catch-all `404`.

external-dns runs in `system-dns`, and only when a zone exists for it to write to: a public domain, a private gateway, or the private CoreDNS zone.

## Requirements

Windsor rejects these combinations when it validates the configuration:

- `dns.private.enabled` needs `dns.private_domain`.
- `gateway.access: private` needs `dns.private_domain`.
- `dns.public_domain` needs `email`, the ACME account contact.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.domain` | string | `test` in dev | Base domain, used when the public and private domains are unset. |
| `dns.public_domain` | string | none | Public zone to create, and the domain for ACME certificates. |
| `dns.private_domain` | string | `dns.domain` | Domain CoreDNS answers for, or the zone behind a private gateway. |
| `dns.private.enabled` | boolean | `true` in dev | Run CoreDNS for the private zone. |

## Reference

- [kustomize/dns](../../../kustomize/dns)
- [kustomize/gateway](../../../kustomize/gateway)
- [terraform/dns/zone](../../../terraform/dns/zone)
