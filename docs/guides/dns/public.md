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

`dns.public_domain` names the zone. The same setting turns on [ACME certificates](../pki/acme.md), and `email` is the ACME account contact the certificates need. The `platform` decides which DNS service holds the zone and how external-dns authenticates to it, as the table below shows.

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
```

With the zone off, Core skips the `dns-zone` component, external-dns, and the cert-manager DNS-01 identity. The `external` gateway gets a certificate from the `public-selfsigned` issuer instead. DNS-01 writes its challenge into the zone, so `pki.public_issuer: acme` fails validation while `dns.public_zone` is `false`.

## Reference

- [terraform/dns/zone/route53](../../../terraform/dns/zone/route53)
- [terraform/dns/zone/azure-dns](../../../terraform/dns/zone/azure-dns)
- [terraform/dns/zone/gcp-dns](../../../terraform/dns/zone/gcp-dns)
- [terraform/dns/zone/hetzner](../../../terraform/dns/zone/hetzner)
- [kustomize/dns](../../../kustomize/dns)
