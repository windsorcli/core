---
title: Cloudflare
description: Cloudflare as the public DNS driver, for public records and Let's Encrypt certificates, or for certificates alone on the internal gateway.
---

The `cloudflare` driver puts the public DNS zone of a context in Cloudflare. `dns.public_domain` decides what Core does with that zone. Set, Core publishes records for the `external` gateway and issues its certificate. Unset, the zone only proves domain ownership to Let's Encrypt, and the `internal` gateway gets a browser-trusted certificate with nothing exposed to the internet.

## Public domain set

With `dns.public_domain` set, Core turns on the `external` gateway, runs external-dns against the zone, and issues the gateway certificate from Let's Encrypt. The context needs a token, the domain, and an `email` for the certificate account:

```yaml
email: admin@example.com
dns:
  public_domain: apps.example.com
  public:
    driver: cloudflare
    cloudflare:
      api_token: ${secret...}
```

`dns.public.cloudflare.zone_name` names the zone when `dns.public_domain` sits below it. The `internal` gateway keeps the cluster CA unless you set `gateway.internal.tls.issuer: acme`.

## Certificates only

A home cluster often serves every app on the `internal` gateway and has nothing reachable from the internet. It can still hold a Let's Encrypt certificate, because the DNS-01 challenge only needs a TXT record in the zone and never contacts the cluster.

Leave `dns.public_domain` unset, name the zone, and set `dns.private_domain` to a name under it:

```yaml
email: admin@example.com
dns:
  private_domain: home.example.com
  public:
    driver: cloudflare
    cloudflare:
      zone_name: example.com
      api_token: ${secret...}
```

Core looks up the `example.com` zone with the Terraform `dns-zone` stack and gives the token to cert-manager. The `public-acme` issuer then solves challenges for `home.example.com`, and the `internal` gateway certificate names it with no `gateway.internal.tls.issuer` setting. The certificate covers `home.example.com` and `*.home.example.com`.

In this mode Core deploys no `external` gateway, no external-dns, and no records in the zone. The cluster needs no public address and no inbound port. The `dns.public_domain` key therefore has two effects: set, it adds the `external` gateway and public records; unset, the zone serves challenges only.

Composition fails in these cases:

| Condition | Fix |
|---|---|
| `dns.public.cloudflare.zone_name` is unset | Set it to the Cloudflare zone. |
| `dns.private_domain` is unset or is not under `zone_name` | Set it to a subdomain of the zone, such as `home.example.com`. |
| `gateway.enabled` is false, or the platform has no `internal` gateway | Enable the gateway; `hetzner` has no `internal` gateway. |
| `gateway.internal.tls.cert` is set, `gateway.internal.tls.issuer` is `ca` or `selfsigned`, or `gateway.internal.https` is false | Remove them, or set `dns.public_domain` to keep the zone for the `external` gateway. |
| `pki.acme.server` is set | Remove it; it selects a private ACME server instead of Let's Encrypt. |
| `dns.public.cloudflare.proxied` is true | Remove it; the zone holds no records to proxy. |

## Token scope

Create a Cloudflare API token with `Zone:Read` and `DNS:Edit` on the one zone, and pass it as `dns.public.cloudflare.api_token` through a secret reference. `create_zone` also needs `Zone:Edit` on the account. The token can edit every record in the zone. In certificate-only mode only cert-manager holds it.

## Certificate Transparency

Let's Encrypt logs every certificate it issues in public Certificate Transparency logs. The `internal` gateway certificate covers `home.example.com` and `*.home.example.com`, so the logs show the private domain and no app hostname. A site that keeps the private domain out of the logs uses the default `private` issuer, which needs no `dns.public.driver`.

## Reference

- [terraform/dns/zone/cloudflare](../../../terraform/dns/zone/cloudflare): looks up or creates the zone.
- [kustomize/pki](../../../kustomize/pki): the `public-acme` issuer and the DNS-01 solver.
- [kustomize/dns](../../../kustomize/dns): external-dns, deployed only when `dns.public_domain` is set.
