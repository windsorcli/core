---
title: Public zones
description: Public DNS zones on AWS, Azure, GCP, or Hetzner, filled by external-dns, plus private zones for a private gateway.
---

With `dns.public_domain` set, Core creates a zone in your cloud provider's DNS service, and external-dns adds a record to it for each route.

## Turn it on

```yaml
platform: aws
dns:
  public_domain: example.com
email: ops@example.com
```

| `platform` | Zone | external-dns provider | Authenticates with |
|---|---|---|---|
| `aws` | Route53 | `route53` | IAM role through Pod Identity |
| `azure` | Azure DNS | `azure` | Workload identity |
| `gcp` | Cloud DNS | `google` | Workload identity |
| `hetzner` | Hetzner DNS | `hetzner` | API token |

The same setting turns on [ACME certificates](../pki/acme.md), and the ACME account needs an `email`.

## Delegate the domain

Core does not register domains, so the new zone is unreachable until you delegate to it. After the first apply, set your registrar's NS records for the domain to the zone's `name_servers`, an output of the `dns-zone` Terraform component.

Do this before you expect a certificate. Let's Encrypt validates through public DNS and finds nothing until the delegation exists. Until then the Certificate stays not ready.

## Private gateway zones

A gateway with `gateway.access: private` publishes to a private zone for `dns.private_domain` and ignores the public one. On AWS, Azure, and GCP the network Terraform component creates that zone and attaches it to the VPC or virtual network, so only hosts on that network can resolve the names. Hetzner has no private zone, and a private gateway there publishes no DNS records.

```yaml
gateway:
  access: private
dns:
  private_domain: internal.example.com
```

external-dns is restricted to the zone by ID on AWS and Azure, and by domain on GCP.

## Reference

- [terraform/dns/zone/route53](../../../terraform/dns/zone/route53)
- [terraform/dns/zone/azure-dns](../../../terraform/dns/zone/azure-dns)
- [terraform/dns/zone/gcp-dns](../../../terraform/dns/zone/gcp-dns)
- [terraform/dns/zone/hetzner](../../../terraform/dns/zone/hetzner)
- [terraform/network](../../../terraform/network)
- [kustomize/dns](../../../kustomize/dns)
