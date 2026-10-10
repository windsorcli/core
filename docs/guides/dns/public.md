---
title: Public zones
description: Public DNS zones on AWS, Azure, GCP, or Hetzner, and VPC-attached private zones, filled by external-dns.
---

With `dns.public_domain` set, Core creates a zone in your cloud provider's DNS service, and external-dns adds a record to it for each route on the `external` gateway.

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

## Use a domain without a zone

A context that does not delegate its domain has no use for the zone. Hetzner, for example, rejects a name under an unsupported TLD such as `single-node.test` when it creates the zone. Set `dns.public_zone: false` to keep the domain as the hostname of the `external` gateway without creating anything in the provider's DNS.

```yaml
platform: hetzner
dns:
  public_domain: single-node.test
  public_zone: false
```

With the zone off, Core skips the `dns-zone` component, external-dns and its token secret, the cert-manager DNS-01 identity, and the delegation message. The `external` gateway still renders and gets a certificate from the `public-selfsigned` issuer. Setting `pki.public_issuer: acme` alongside `dns.public_zone: false` fails validation, because DNS-01 writes its challenge into the zone.

## Delegate the domain

Core does not register domains, so the new zone is unreachable until you delegate to it. After the first apply, set your registrar's NS records for the domain to the zone's `name_servers`, an output of the `dns-zone` Terraform component.

Do this before you expect a certificate. Let's Encrypt validates through public DNS and finds nothing until the delegation exists. Until then the Certificate stays not ready.

## Private zones

With `dns.private_domain` set, the `internal` gateway publishes to a private zone and never to the public one. On AWS, Azure, and GCP the network Terraform component creates the zone and attaches it to the VPC or virtual network, so only hosts on that network can resolve the names. Hetzner has no private zone and rejects `dns.private_domain` outside dev mode.

```yaml
dns:
  public_domain: example.com
  private_domain: internal.example.com
```

Both domains can be set together. Each gets its own external-dns instance, restricted to its zone by ID on AWS and Azure, and by domain on GCP.

## Reference

- [terraform/dns/zone/route53](../../../terraform/dns/zone/route53)
- [terraform/dns/zone/azure-dns](../../../terraform/dns/zone/azure-dns)
- [terraform/dns/zone/gcp-dns](../../../terraform/dns/zone/gcp-dns)
- [terraform/dns/zone/hetzner](../../../terraform/dns/zone/hetzner)
- [terraform/network](../../../terraform/network)
- [kustomize/dns](../../../kustomize/dns)
