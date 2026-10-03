---
title: PKI
description: TLS certificates through cert-manager, from Let's Encrypt, a private CA, or a self-signed issuer, with trust-manager to distribute the CA.
sidebar_order: 5
---

cert-manager runs in every cluster and issues the [gateway](../gateway/index.md) certificate, along with the certificates a few add-ons need internally. A public domain gets [Let's Encrypt](acme.md). Everything else gets a [private CA](private-ca.md) or a self-signed issuer. The following config can be placed in a context's `values.yaml` file to choose.

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
| `public-acme` | [Let's Encrypt](acme.md) | `dns.public_domain` is set. |
| `public-selfsigned` | A self-signed certificate per request. | `dns.public_domain` is unset, on cloud platforms and in dev mode. |
| `private` | The [private CA](private-ca.md) if `pki.enabled`, otherwise a self-signed certificate per request. | Always. |

The gateway certificate uses the first row that matches:

| Condition | Issuer |
|---|---|
| `gateway.access: private` with `dns.private_domain` set | `private` |
| `dns.public_domain` is set | `public-acme` |
| `platform` is `aws`, `azure`, or `hetzner`, and no public domain | `public-selfsigned` |
| Anything else, such as a local cluster | `private` |

When the match changes, the Certificate's issuer name changes with it, and cert-manager reissues into the same Secret. Workloads see the new certificate at the same name.

`private` also issues the certificates between CoreDNS and its etcd for [private DNS](../dns/private.md), whichever issuer the gateway uses.

## Self-signed certificates

A self-signed issuer needs no setup. Each certificate it signs is its own root, though, so browsers warn about every one and clients cannot trust them as a group. It works as a starting point until you set `dns.public_domain` or `pki.enabled`.

## Monitoring

With `telemetry.metrics.enabled` (the default), Prometheus scrapes cert-manager. `observability.enabled` adds a cert-manager dashboard.

## Operations

On docker-desktop and Colima, cert-manager's controller can restart after the host sleeps, logging `clockHealth failed: the system clock is out of sync` with `Reason: Completed`. The VM's wall clock jumps forward on wake while the controller's monotonic clock does not, and the restart resets it. The restarts stop once the VM's clock settles.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.public_domain` | string | none | Turns on ACME certificates for this domain. See [DNS](../dns/index.md). |
| `email` | string | none | ACME account contact. Windsor requires it with `dns.public_domain`. |
| `pki.enabled` | boolean | `true` in dev, otherwise `false` | Run a private CA with trust-manager. |
| `pki.private_ca.cert` | string | generated | PEM root certificate. Set together with `key`. Accepts `${secret(...)}`. |
| `pki.private_ca.key` | string | generated | PEM root private key. Set together with `cert`. Accepts `${secret(...)}`. |
| `policies.enabled` | boolean | `true` | Installs the Kyverno policy that mounts the CA bundle into labeled pods. |

## Reference

- [kustomize/pki](../../../kustomize/pki)
- [kustomize/crds](../../../kustomize/crds)
- [kustomize/policy](../../../kustomize/policy)
- [terraform/pki/ca](../../../terraform/pki/ca)
