---
title: Public zones
description: Public DNS zones on AWS, Azure, GCP, or Hetzner, filled by external-dns from the routes of the external gateway.
---

A client on the internet reaches `my-app.example.com` only when a public DNS service answers for `example.com`. When you set `dns.public_domain`, Core makes a [public zone](index.md) in the DNS service of your cloud provider. external-dns adds a record to the zone for each route on the `external` gateway.

## Turn it on

This `values.yaml` makes a Route53 zone for `example.com` on AWS:

```yaml
platform: aws
dns:
  public_domain: example.com
email: ops@example.com
```

`dns.public_domain` names the zone. Core writes this zone, so the same setting enables [Let's Encrypt certificates](../pki/acme.md) for the `external` gateway. `email` is the ACME account contact that the certificates need.

`platform` selects the DNS service for the zone. It also selects how external-dns authenticates, as this table shows.

| `platform` | Zone | external-dns provider | Authenticates with |
|---|---|---|---|
| `aws` | Route53 | `route53` | IAM role through Pod Identity |
| `azure` | Azure DNS | `azure` | Workload identity |
| `gcp` | Cloud DNS | `google` | Workload identity |
| `hetzner` | Hetzner DNS | `hetzner` | API token |

## Delegate the domain

Core does not register domains. Clients cannot reach the new zone until you delegate the domain to it. After the first apply, set the NS records of the domain at your registrar. Use the `name_servers` output of the `dns-zone` Terraform component.

> [!IMPORTANT]
> The ACME certificate is not ready until the delegation exists.

On Hetzner, Terraform can make the NS records. Set `hetzner.dns_parent_zone` to a parent zone in the same Hetzner account. Then set `dns.public_domain` to a name under that zone:

```yaml
hetzner:
  dns_parent_zone: example.com
dns:
  public_domain: hetzner.example.com
```

## Use a domain without a zone

Some domains cannot be delegated, for example a name under a TLD that nobody can register, such as `single-node.test`. For these domains, set `dns.public_zone: false`. The domain stays the hostname of the `external` gateway, and Core makes nothing in the DNS service of the provider. This Hetzner context uses such a domain:

```yaml
platform: hetzner
dns:
  public_domain: single-node.test
  public_zone: false
gateway:
  external:
    tls:
      issuer: selfsigned
```

Without the zone, Core does not install the `dns-zone` component, external-dns, or the cert-manager DNS-01 identity. Let's Encrypt validates through the zone. Outside dev mode, the `external` gateway thus needs a different certificate source. `gateway.external.tls.issuer: selfsigned` is the simplest. [Gateway certificates](../pki/index.md#gateway-certificates) lists the other sources.

When `dns.public_zone` is `false`, validation fails for `gateway.external.tls.issuer: acme`. The exception is when `pki.acme.server` names your own ACME server.

## Reference

- [terraform/dns/zone/route53](../../../terraform/dns/zone/route53)
- [terraform/dns/zone/azure-dns](../../../terraform/dns/zone/azure-dns)
- [terraform/dns/zone/gcp-dns](../../../terraform/dns/zone/gcp-dns)
- [terraform/dns/zone/hetzner](../../../terraform/dns/zone/hetzner)
- [kustomize/dns](../../../kustomize/dns)
