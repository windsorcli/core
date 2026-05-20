---
title: dns/zone
description: Picks the public DNS zone provider (Route53 or Azure DNS) for cert-manager ACME and external-dns.
---

# dns/zone

Provisions a public DNS zone for a domain, kept independent of any
network or cluster module so the zone has its own lifecycle. The
zone is consumed by cert-manager (ACME DNS-01 solver) and
external-dns (record automation).

Two sibling modules implement the same role on different clouds;
exactly one runs per `windsor apply`, selected by the active
platform facet:

| Module | Platform | Provisioned |
|---|---|---|
| [`route53`](route53/) | `platform: aws` | Public Route53 hosted zone, optional DNSSEC, optional query logging |
| [`azure-dns`](azure-dns/) | `platform: azure` | Public Azure DNS zone, optional dedicated resource group |

Both modules:

- Are gated on the operator setting `dns.public_domain` in `values.yaml` — the facet only emits this stack when a public domain is configured.
- Own their own resource group / lifecycle so the cluster's teardown doesn't drag the zone (and the registrar's NS-delegation effort) down with it.
- Expose a `name_servers` output the operator publishes at the domain registrar so public DNS resolution flows through this zone.
- Expose a `zone_id` (Route53 hosted zone ID, or full Azure resource ID) used by the cluster module to scope cert-manager's IAM / RBAC role to just this zone.

## Wiring

Both variants are wired by their platform facets, gated on
`dns.public_domain`:

```yaml
terraform:
  - name: dns-zone
    path: dns/zone/route53          # or dns/zone/azure-dns
    when: "(dns.public_domain ?? '') != ''"
    inputs:
      domain_name: <dns.public_domain>
```

How that flows from `values.yaml`:

- `domain_name` — `dns.public_domain`. Required; the zone is named after this domain.

Optional knobs (Route53 DNSSEC, query logging; Azure DNS location +
resource group) keep their module defaults. Override per-context via
tfvars at `contexts/<context>/terraform/dns-zone.tfvars`.

## After apply

Both modules expose `name_servers` — publish those at the domain
registrar so public DNS queries delegate to this zone. Until the
NS-side handoff completes, ACME validations against this zone
won't succeed.

## See also

- [dns/zone/route53](route53/) — AWS public DNS zone.
- [dns/zone/azure-dns](azure-dns/) — Azure public DNS zone.
- [`cluster/aws-eks`](../../cluster/aws-eks/) / [`cluster/azure-aks`](../../cluster/azure-aks/) — consume `zone_id` to scope cert-manager and external-dns identities.
- [platform-aws.yaml](../../../contexts/_template/facets/platform-aws.yaml) / [platform-azure.yaml](../../../contexts/_template/facets/platform-azure.yaml) — facet wiring.
