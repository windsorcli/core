---
title: PKI
description: TLS certificates through cert-manager, from Let's Encrypt, a private CA, or a self-signed issuer, with trust-manager to distribute the CA.
sidebar_order: 5
---

cert-manager runs in every cluster and issues the certificate for each [gateway](../gateway/index.md), along with the certificates a few add-ons need internally. A public domain gets [Let's Encrypt](acme.md). Everything else gets a [private CA](private-ca.md) or a self-signed issuer. The following config can be placed in a context's `values.yaml` file to choose.

```yaml
dns:
  public_domain: example.com   # ACME certificates from Let's Encrypt
email: ops@example.com
pki:
  enabled: true                # private CA with trust-manager
```

## Issuers

Core defines three `ClusterIssuer` resources, which add-ons refer to by name.

| Issuer | Signs with | Exists when |
|---|---|---|
| `public-acme` | [Let's Encrypt](acme.md) | `dns.public_domain` is set on a cloud platform, `dns.public_zone` is not `false`, and `pki.public_issuer` is not `selfsigned`. |
| `public-selfsigned` | A self-signed certificate per request. | `public-acme` does not exist. |
| `private` | The [private CA](private-ca.md) if `pki.enabled`, otherwise a self-signed certificate per request. | Always. |

Each Gateway picks its issuer from its own domain.

| Gateway | Condition | Issuer |
|---|---|---|
| `external` | `dns.public_domain` is set and `platform` is `aws`, `azure`, `gcp`, or `hetzner` | `public-acme` |
| `external` | `dns.public_domain` is set, and `platform` is another platform, `pki.public_issuer` is `selfsigned`, or `dns.public_zone` is `false` | `public-selfsigned` |
| `internal` | `dns.private_domain` is set | `private` |

An `internal` Gateway always uses `private`, because DNS-01 cannot validate a zone that exists only inside a VPC or on a workstation. When an issuer name changes, the Certificate's issuer name changes with it, and cert-manager reissues into the same Secret. Workloads see the new certificate at the same name.

`private` also issues the certificates between CoreDNS and its etcd for [private DNS](../dns/private.md), whichever issuer the gateway uses.

## Self-signed certificates

A self-signed issuer needs no setup. Each certificate it signs is its own root, though, so browsers warn about every one and clients cannot trust them as a group. It works as a starting point until you set `pki.enabled`, or, for the `external` Gateway on a cloud platform, `dns.public_domain` without `pki.public_issuer: selfsigned`.

## Monitoring

With `telemetry.metrics.enabled` (the default), Prometheus scrapes cert-manager. `observability.enabled` adds a cert-manager dashboard.

## Operations

On docker-desktop and Colima, cert-manager's controller can restart after the host sleeps, logging `clockHealth failed: the system clock is out of sync` with `Reason: Completed`. The VM's wall clock jumps forward on wake while the controller's monotonic clock does not, and the restart resets it. The restarts stop once the VM's clock settles.

## Configuration

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
