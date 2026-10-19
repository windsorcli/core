---
title: PKI
description: TLS certificates through cert-manager, from Let's Encrypt, a private CA, or a self-signed issuer, with trust-manager to distribute the CA.
sidebar_order: 5
---

Every [gateway](../gateway/index.md) serves TLS, so before `my-app.example.com` answers over HTTPS, something has to sign a certificate for it. In Windsor that is *cert-manager*, which runs in every cluster and issues the certificate for each gateway along with the certificates a few add-ons need internally. A public domain gets its certificate from [Let's Encrypt](acme.md). Everything else gets one from a [private CA](private-ca.md) or a self-signed issuer.

You choose between them in a context's `values.yaml`. This example, which the other PKI pages reuse, asks for both kinds.

```yaml
dns:
  public_domain: example.com     # ACME certificates from Let's Encrypt
  private_domain: example.internal
email: ops@example.com
pki:
  enabled: true                  # private CA with trust-manager
```

`dns.public_domain` turns on Let's Encrypt certificates for `example.com`, and `email` is the contact Let's Encrypt keeps on the account. `pki.enabled` runs a private CA, plus *trust-manager*, which distributes that CA to workloads that opt in. `dns.private_domain` gives the cluster an `internal` gateway for `example.internal`, whose certificate always comes from the private side.

## Issuers

cert-manager signs through an *issuer*, a resource that names a certificate authority and how to reach it. Core defines three cluster-wide issuers as `ClusterIssuer` resources, and add-ons refer to them by name. This table lists each one, what it signs with, and when it exists.

| Issuer | Signs with | Exists when |
|---|---|---|
| `public-acme` | [Let's Encrypt](acme.md) | `dns.public_domain` is set on a cloud platform, `dns.public_zone` is not `false`, and `pki.public_issuer` is not `selfsigned`. |
| `public-selfsigned` | A self-signed certificate per request. | On AWS, Azure, GCP, and Hetzner, whenever `public-acme` does not exist. Elsewhere, when `dns.public_domain` is set. Always in dev mode. |
| `private` | The [private CA](private-ca.md) if `pki.enabled`, otherwise a self-signed certificate per request. | Always. |

Each Gateway picks its issuer from its own domain. With the example `values.yaml` on AWS, the `external` Gateway for `example.com` uses `public-acme`, and the `internal` Gateway for `example.internal` uses `private`. Run the same `values.yaml` on a local platform and the `external` Gateway falls back to `public-selfsigned`. This table gives the issuer each Gateway selects under every condition.

| Gateway | Condition | Issuer |
|---|---|---|
| `external` | `dns.public_domain` is set and `platform` is `aws`, `azure`, `gcp`, or `hetzner` | `public-acme` |
| `external` | `dns.public_domain` is set, and `platform` is another platform, `pki.public_issuer` is `selfsigned`, or `dns.public_zone` is `false` | `public-selfsigned` |
| `internal` | `dns.private_domain` is set | `private` |

An `internal` Gateway always uses `private`. Let's Encrypt validates a wildcard through a *DNS-01* challenge, a record it looks up in the public zone, and that lookup cannot reach a zone that exists only inside a VPC or on a workstation.

Switching issuers does not disturb the workloads that read a certificate. When a Gateway's issuer changes, cert-manager reissues its certificate into the same Secret, so workloads keep reading the same name.

`private` also issues the certificates between CoreDNS and its etcd for [private DNS](../dns/private.md), whichever issuer the gateway uses.

## Self-signed certificates

A self-signed issuer needs no setup. Each certificate it signs is its own root, though, so clients cannot trust those certificates as a group.

> [!NOTE]
> Browsers warn about every self-signed certificate.

You can move off self-signed certificates in two ways. Set `pki.enabled` to sign with a private CA instead, or set `dns.public_domain` on a cloud platform to get ACME for the `external` Gateway.

## Monitoring

With `telemetry.metrics.enabled` (the default), Prometheus scrapes cert-manager. `observability.enabled` adds a cert-manager dashboard.

## Operations

On docker-desktop and Colima, cert-manager's controller can restart after the host sleeps. It logs `clockHealth failed: the system clock is out of sync` with `Reason: Completed`. On wake, the VM's wall clock jumps forward while the controller's monotonic clock does not, and the restart resets it.

> [!NOTE]
> The restarts stop once the VM's clock settles.

## Configuration

This table lists every `values.yaml` key the PKI guides use.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.public_domain` | string | none | Turns on ACME certificates for this domain. See [DNS](../dns/index.md). |
| `pki.public_issuer` | string | `acme` when `dns.public_domain` is set on a cloud platform, otherwise `selfsigned` | `acme` or `selfsigned`. `selfsigned` keeps the public zone but issues no Let's Encrypt certificate. |
| `email` | string | none | ACME account contact. Windsor requires it when the `external` gateway uses `public-acme`. |
| `pki.enabled` | boolean | `true` in dev, otherwise `false` | Run a private CA with trust-manager. |
| `pki.private_ca.cert` | string | generated | PEM root certificate. Set together with `key`. Accepts `${secret(...)}`. |
| `pki.private_ca.key` | string | generated | PEM root private key. Set together with `cert`. Accepts `${secret(...)}`. |
| `policies.enabled` | boolean | `true` | Installs the Kyverno policy that mounts the CA bundle into labeled pods. |

## Reference

- [kustomize/pki](../../../kustomize/pki)
- [kustomize/crds](../../../kustomize/crds)
- [kustomize/policy](../../../kustomize/policy)
- [terraform/pki/ca](../../../terraform/pki/ca)
