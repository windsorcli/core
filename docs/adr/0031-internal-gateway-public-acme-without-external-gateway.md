---
title: "ADR-0031: The cloudflare driver issues the internal gateway certificate without a public domain"
description: When dns.public.driver is cloudflare and dns.public_domain is unset, the Cloudflare zone serves only DNS-01. The internal gateway gets a public-acme certificate for dns.private_domain, and Core turns on no external gateway, no external-dns, and no public records.
---

# ADR-0031: The cloudflare driver issues the internal gateway certificate without a public domain

## Status

Proposed (2026-11-18). Builds on
[ADR-0001](0001-internal-external-gateways-and-dns.md),
[ADR-0019](0019-explicit-endpoints-dhcp-and-tls-sources.md), and
[ADR-0030](0030-cloudflare-public-dns-driver.md). It amends ADR-0030
sections 1, 4, and 10, and the gateway issuer inference of ADR-0019
section 6 (see section 7).

This is a new ADR and not an amendment to ADR-0030 for two reasons.
ADR-0030 section 10 leaves a certificate-only mode to "a later ADR", and
ADR-0030 is merged and implemented, so its text records shipped
behavior. The change also edits the issuer inference that ADR-0019
owns, which is outside the scope of a DNS driver.

## Context

A home cluster on `metal`, `incus`, or `proxmox` serves its apps on the
`internal` gateway only. The user owns a domain on Cloudflare and wants
Let's Encrypt certificates, so that phones and tablets trust the apps
with no private root installed. Nothing in the cluster faces the
internet.

`main` cannot express this today:

- `addon-public-dns.yaml` requires `dns.public_domain` for every
  `dns.public.driver`.
- `dns.public_domain` turns on the `external` gateway
  (`gateway_effective.external_enabled`), and
  `gateway.external.enabled: false` is rejected while the domain is set.
  On these platforms the gateway also needs its own `gateway.external.ip`
  or node port.
- With `dns.public_domain` set, external-dns publishes the gateway
  address to the public zone, and CoreDNS serves the public zone inside
  the cluster (`dns_private_effective.public_zone`).
- ADR-0030 section 4 keeps the `internal` gateway on the `private`
  issuer on non-cloud platforms, even when `dns.private_domain` is a
  subdomain of `dns.public_domain`. A context opts in with
  `gateway.internal.tls.issuer: acme`.

So the only path to a `public-acme` certificate on the `internal`
gateway also creates an `external` gateway, a second address, and public
records. Other facets pick the external gateway from `dns.public_domain`
too: `addon-identity.yaml` moves Keycloak to the external gateway when
the domain is set.

DNS-01 does not need any of that. cert-manager writes one TXT record,
`_acme-challenge.<name>`, into the zone that holds the name. The
Cloudflare solver finds that zone through the API token. A wildcard
`*.home.example.com` certificate needs only the zone `example.com`, the
token, and no record that points at the cluster.

## Decision

### 1. The mode and the values that turn it on

A context is in certificate-only mode when `dns.public.driver` is
`cloudflare` and `dns.public_domain` is unset. These values turn it on:

```yaml
email: admin@example.com
dns:
  private_domain: home.example.com     # the internal gateway domain, under the zone
  public:
    driver: cloudflare
    cloudflare:
      zone_name: example.com           # required in this mode
      api_token: ${secret...}          # Zone:Read and DNS:Edit on the zone
```

No new key is added. The mode follows from facts the context already
states: it owns a Cloudflare zone and it has no public domain. This
follows ADR-0019 section 6, where `values.yaml` states site facts and
Core infers the issuers.

Each of the three parts turns on from these values:

| Part | Turned on by | What Core deploys |
| --- | --- | --- |
| Public zone | `dns.public.driver: cloudflare` and `dns.public.cloudflare.zone_name` | The `dns-zone` stack on `terraform/dns/zone/cloudflare`, which looks up the zone, or creates it with `create_zone` |
| DNS-01 solver | the public zone and `dns.public.cloudflare.api_token` | The Secret `cloudflare-dns` in `system-pki`, and the `public-issuer/acme/cloudflare` component |
| `public-acme` issuer | the solver, `dns.private_domain`, and `email` | The `public-acme` ClusterIssuer, which the `internal` gateway certificate names |

The solver selects `dnsZones: [dns.private_domain]` in this mode. In
the ADR-0030 mode it keeps `dns.public_domain`.

Core MUST NOT deploy any of these in certificate-only mode:

- the `external` gateway, which stays off because `dns.public_domain` is
  unset;
- the `dns` flux entry of `addon-public-dns.yaml`, so no external-dns
  instance writes to the Cloudflare zone and no `cloudflare-dns` Secret
  is placed in `system-dns`;
- the CoreDNS public zone, which `dns_private_effective.public_zone`
  already leaves off without `dns.public_domain`.

The zone never holds a record that points at the cluster. The cluster
needs no public address and no inbound port.

### 2. The internal gateway issuer

In certificate-only mode, the `internal` gateway issuer resolves to
`public-acme` with no override. The setting exists only to issue that
certificate, so it states the intent that ADR-0030 section 4 asks a
context to state with `gateway.internal.tls.issuer: acme`.

The ADR-0030 mode does not change. With `dns.public_domain` set and the
`cloudflare` driver, the `internal` gateway keeps the `private` issuer
on non-cloud platforms unless `gateway.internal.tls.issuer` is `acme`.

cert-manager MUST check DNS-01 propagation through public resolvers,
because CoreDNS answers for `dns.private_domain` inside the cluster
(ADR-0019 section 7). The resolver rule already turns this on whenever
the `internal` issuer is `public-acme`.

### 3. Defaults on metal, Incus, and Proxmox

The default does not change: a context that sets only
`dns.private_domain` gets the `private` issuer and no public zone.
Certificate-only mode is opt-in through `dns.public.driver`, because
Core cannot know that the user owns a Cloudflare zone.

| Values set | `internal` issuer | `external` gateway | Public records |
| --- | --- | --- | --- |
| `dns.private_domain` | `private` | none | none |
| `dns.private_domain`, `pki.acme.server` | `private-acme` | none | none |
| `dns.private_domain` under `zone_name`, `dns.public.driver: cloudflare` | `public-acme` | none | none |
| the row above, plus `dns.public_domain` | `private`, or `public-acme` with `gateway.internal.tls.issuer: acme` | on, `public-acme` | the external gateway address |

The same rules apply on every other platform that has an `internal`
gateway. `hetzner` has no `internal` gateway, so the mode is not
available there.

### 4. Composition errors

The `requires:` rules below MUST fail composition in certificate-only
mode. Each message names only `values.yaml` keys.

| Condition | Message names |
| --- | --- |
| `dns.public.cloudflare.zone_name` is unset | `dns.public.cloudflare.zone_name` (a `paths:` rule) |
| `dns.private_domain` is unset, or is not a subdomain of `zone_name` | `dns.private_domain`, `dns.public.cloudflare.zone_name` |
| `gateway.enabled` is false, or the platform has no `internal` gateway | `gateway.enabled`, `dns.public.driver` |
| `gateway.internal.tls.cert` is set, `gateway.internal.tls.issuer` is `ca` or `selfsigned`, or `gateway.internal.https` is false | those keys, and `dns.public_domain` as the way to keep the zone for the external gateway |
| `pki.acme.server` is set | `pki.acme.server`, `dns.public.driver` |
| `dns.public.cloudflare.proxied` is true | `dns.public.cloudflare.proxied` |

The rules that ADR-0030 already defines keep applying:
`dns.public.cloudflare.api_token` is required, `account_id` is required
with `create_zone`, `email` is required with `public-acme`, and
`dns.public_zone: false` is rejected with a driver.

`dns.public.driver: cloud` still requires `dns.public_domain`. The
platform zone modules create a zone named exactly that domain, so they
have no zone to look up in this mode.

When the tunnel of ADR-0029 ships, the facet MUST also reject
`tunnel.driver` in this mode, because a tunnel fronts the `external`
gateway.

### 5. Certificate Transparency

Let's Encrypt logs every certificate it issues. The `internal` gateway
certificate covers `home.example.com` and `*.home.example.com`, so the
logs show the private domain but no app hostname. The guide MUST say
this. A site that keeps the private domain out of the logs uses the
`private` issuer, which is the default.

### 6. Facet changes

- `platform-base.yaml` adds `dns_zone_effective.certificate_only`, true
  when the public driver is `cloudflare` and `dns.public_domain` is
  unset. `dns_zone_effective.cloudflare` becomes true in this mode as
  well.
- `tls_effective.internal_issuer` resolves to `public-acme` in this
  mode, after the overrides and before the `private` fallback.
- `addon-public-dns.yaml` requires `dns.public_domain` only for the
  `cloud` driver, adds the rules of section 4, and gates its `dns` flux
  entry on `dns_zone_effective.certificate_only != true`.
- The `option-gateway.yaml` rule for `gateway.internal.tls.issuer: acme`
  accepts certificate-only mode as a source.

`dns_zone_effective.enabled` keeps its meaning: a zone for
`dns.public_domain`. Every consumer that reads `dns.public_domain` to
choose the external gateway stays correct, because the domain is unset.

The implementation SHOULD start after
[core#3510](https://github.com/windsorcli/core/pull/3510) merges,
because both change `platform-base.yaml` and `addon-public-dns.yaml`.

### 7. Amendments

- ADR-0030 section 1: `dns.public_domain` is required for the `cloud`
  driver only. The `cloudflare` driver without it is certificate-only
  mode.
- ADR-0030 section 4: the `internal` gateway rule gains the exception in
  section 2 of this ADR.
- ADR-0030 section 10: the last paragraph is replaced. A cluster that
  wants a certificate and no public record sets the `cloudflare` driver
  without `dns.public_domain`.
- ADR-0019 section 6, gateway issuer inference: a row for the `internal`
  gateway, "`dns.public.driver` is `cloudflare` and `dns.public_domain`
  is unset: public ACME, with DNS-01 in the Cloudflare zone". The row
  sits after the `pki.acme.server` row, and section 4 of this ADR
  rejects that combination.

### 8. Tests and docs

- Facet tests in `addon-public-dns.test.yaml` and the gateway tests.
  Cases on `metal`: the mode with no external gateway, no `dns` flux
  entry, the `dns-zone` stack, and the `internal` issuer `public-acme`;
  the solver zone set to `dns.private_domain`; each error in section 4;
  the ADR-0030 mode unchanged, with the `internal` gateway on `private`.
  One case on `incus` and one on `proxmox` check the issuer.
- Docs: the Cloudflare guide gains a section for this mode. It states
  the values, the token scope, that the cluster needs no public
  address, and the Certificate Transparency note.

## Consequences

- A home or lab cluster gets browser-trusted certificates on the
  `internal` gateway with one zone, one token, and no inbound exposure.
- The `home` blueprint can set this mode as its DNS and TLS default
  without the `external` gateway.
- The in-cluster token can still edit every record in the zone, as in
  ADR-0030. In this mode only cert-manager holds it.
- `dns.public_domain` now has two effects for the `cloudflare` driver:
  set, it adds the `external` gateway and public records; unset, the
  zone serves DNS-01 only. The guide MUST state both.
- The certificate depends on the Cloudflare API at each renewal. A
  failed renewal shows in the expiry alerts of ADR-0019 section 6.

## Alternatives considered

- **Let `gateway.external.enabled: false` turn off the external gateway
  while `dns.public_domain` is set.** The domain still drives
  external-dns, the CoreDNS public zone, and the gateway choice in
  `addon-identity.yaml` and `option-demo.yaml`. Each of those would need
  a second gate, and a missed one routes a service to a gateway that
  does not exist.
- **A flag such as `dns.public.cloudflare.certificates_only: true`.** It
  restates a fact that the unset `dns.public_domain` already states, and
  it adds an invalid combination (the flag with a public domain) to
  reject.
- **Infer `public-acme` for the internal gateway whenever the
  `cloudflare` driver is set, as on the cloud platforms.** It reverses
  ADR-0030 decision 7 for contexts that set both domains. This ADR
  leaves that decision alone.
- **Certificate-only mode for the `cloud` driver.** The platform zone
  modules create a zone named `dns.public_domain` and have no lookup
  path. No home platform uses them. A later ADR MAY add it.
