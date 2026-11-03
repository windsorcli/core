---
title: Public zones
description: Public DNS zones on AWS, Azure, GCP, or Hetzner, filled by external-dns from the external gateway's routes.
---

A client on the internet can reach `my-app.example.com` only if a public DNS service answers for `example.com`. With `dns.public_domain` set, Core creates a [public zone](index.md) in your cloud provider's DNS service, and external-dns adds a record to it for each route on the `external` gateway.

## Turn it on

This `values.yaml` creates a Route53 zone for `example.com` on AWS:

```yaml
platform: aws
dns:
  public_domain: example.com
email: ops@example.com
```

`dns.public_domain` names the zone. Because Core writes this zone, the same setting turns on [Let's Encrypt certificates](../pki/acme.md) for the `external` gateway, and `email` is the ACME account contact the certificates need. The `platform` decides which DNS service holds the zone and how external-dns authenticates to it, as the table below shows.

| `platform` | Zone | external-dns provider | Authenticates with |
|---|---|---|---|
| `aws` | Route53 | `route53` | IAM role through Pod Identity |
| `azure` | Azure DNS | `azure` | Workload identity |
| `gcp` | Cloud DNS | `google` | Workload identity |
| `hetzner` | Hetzner DNS | `hetzner` | API token |

## Delegate the domain

Core does not register domains, so the new zone is unreachable until you delegate to it. After the first apply, set your registrar's NS records for the domain to the zone's `name_servers`, an output of the `dns-zone` Terraform component.

> [!IMPORTANT]
> The ACME certificate stays not ready until the delegation exists.

On Hetzner, Terraform can create the NS records for you. Set `hetzner.dns_parent_zone` to a parent zone in the same Hetzner account, and make `dns.public_domain` a name under it:

```yaml
hetzner:
  dns_parent_zone: example.com
dns:
  public_domain: hetzner.example.com
```

## Use a domain without a zone

Some domains will never be delegated, such as a name under an unregistrable TLD like `single-node.test`. Set `dns.public_zone: false` for those. The domain stays the `external` gateway's hostname, and Core creates nothing in the provider's DNS. This Hetzner context uses one:

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

With the zone off, Core skips the `dns-zone` component, external-dns, and the cert-manager DNS-01 identity. Let's Encrypt validates through that zone, so the `external` gateway needs another certificate source outside dev mode. `gateway.external.tls.issuer: selfsigned` is the simplest, and [Gateway certificates](../pki/index.md#gateway-certificates) lists the rest. `gateway.external.tls.issuer: acme` fails validation while `dns.public_zone` is `false`, unless `pki.acme.server` names an ACME server of your own.

## Reference

- [terraform/dns/zone/route53](../../../terraform/dns/zone/route53)
- [terraform/dns/zone/azure-dns](../../../terraform/dns/zone/azure-dns)
- [terraform/dns/zone/gcp-dns](../../../terraform/dns/zone/gcp-dns)
- [terraform/dns/zone/hetzner](../../../terraform/dns/zone/hetzner)
- [kustomize/dns](../../../kustomize/dns)
