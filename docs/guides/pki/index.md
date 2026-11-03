---
title: PKI
description: TLS certificates through cert-manager, from Let's Encrypt, an internal ACME server, the cluster CA, or a certificate the site supplies, with trust-manager to distribute the CA.
sidebar_order: 5
---

Every [gateway](../gateway/index.md) serves TLS, so before `my-app.example.com` answers over HTTPS, something has to sign a certificate for it. In Windsor that is *cert-manager*, which runs in every cluster and issues the certificate for each gateway along with the certificates a few add-ons need internally. Which authority signs a gateway's certificate depends on what the site has: a public zone Core can write, an ACME server of its own, a corporate CA, or nothing at all.

`values.yaml` states those facts, and Core picks every issuer from them. This example, which the other PKI pages reuse, sets two domains and an ACME contact.

```yaml
dns:
  public_domain: example.com
  private_domain: int.example.com
email: ops@example.com
```

`dns.public_domain` gives the cluster an `external` gateway for `example.com`, and `dns.private_domain` gives it an `internal` gateway for `int.example.com`. `email` is the contact Let's Encrypt keeps on the account. On AWS both gateways get Let's Encrypt certificates. On metal, `internal` gets one from the [cluster CA](private-ca.md), which every cluster runs along with *trust-manager*, the controller that distributes the CA to workloads that opt in.

## Issuers

cert-manager signs through an *issuer*, a resource that names a certificate authority and how to reach it. Core defines cluster-wide issuers as `ClusterIssuer` resources with fixed names, and add-ons refer to them by name. This table lists each one, what it signs with, and when it exists.

| Issuer | Signs with | Exists when |
|---|---|---|
| `public-acme` | [Let's Encrypt](acme.md), through DNS-01 in the public zone Core writes. | A gateway uses it. |
| `private-acme` | The [internal ACME server](acme.md#internal-acme-server) in `pki.acme.server`. | A gateway uses it. |
| `public-selfsigned` | A self-signed certificate per request. | A gateway uses it. Also on AWS, Azure, GCP, and Hetzner whenever no gateway uses `public-acme`, and always in dev mode. |
| `private` | The [cluster CA](private-ca.md). | Always. |

`private` also issues the certificates between CoreDNS and its etcd for [private DNS](../dns/private.md), and every other workload certificate an add-on requests, whichever issuer the gateways use.

When a gateway's issuer changes, cert-manager reissues its certificate into the same Secret, so the gateway keeps reading the same name.

## Gateway certificates

Each gateway infers its issuer on its own. A gateway that sets `gateway.<name>.tls.cert` serves that [supplied certificate](supplied.md) and uses no issuer. A gateway that sets `gateway.<name>.tls.issuer` uses the issuer it names. Otherwise Core walks the conditions in this table from the top and takes the first that holds.

| Gateway | Condition | Issuer |
|---|---|---|
| `external` | Core writes the public zone: `dns.public_domain` on AWS, Azure, GCP, or Hetzner, with `dns.public_zone` left `true` | `public-acme` |
| `external` | `pki.acme.server` is set | `private-acme` |
| `external` | dev mode | `public-selfsigned` |
| `external` | otherwise | none, and Windsor rejects the configuration |
| `internal` | `pki.acme.server` is set | `private-acme` |
| `internal` | `dns.private_domain` is a subdomain of `dns.public_domain`, and Core writes the public zone | `public-acme` |
| `internal` | otherwise | `private` |

The `internal` rows explain why the private domain SHOULD be a [subdomain of the public one](../dns/index.md#domains-and-gateways). Let's Encrypt validates a wildcard through a DNS-01 record it looks up in the public zone. For `int.example.com` that record lives in `example.com`, which Core already writes, so the `internal` gateway gets a certificate every browser trusts. A private domain outside the public zone has nowhere public to put the record.

`gateway.<name>.tls.issuer` takes one of three values. `ca` uses `private`, which suits a site that keeps internal hostnames out of Certificate Transparency logs. `acme` uses `pki.acme.server` or Let's Encrypt, and fails validation when neither is available to that gateway. `selfsigned` uses `public-selfsigned` and is meant for testing.

> [!NOTE]
> Browsers warn about every self-signed certificate, because each one is its own root.

The deprecated `pki.public_issuer: selfsigned` still acts as `gateway.external.tls.issuer: selfsigned`.

## Choosing a source on-prem

A cluster on metal, vSphere, Hyper-V, Incus, or Proxmox has more choices to make, because its clients are often plant-floor devices that trust only the site's own roots. The options below run in order of preference. Each needs more from the site than the one after it, and gives clients a certificate they trust with less work.

1. Public ACME on a subdomain. When Core writes the public zone and `dns.private_domain` sits under `dns.public_domain`, both gateways get Let's Encrypt certificates and no client needs a private root. Core writes public zones only on AWS, Azure, GCP, and Hetzner, so an on-prem cluster cannot use this option yet. See [ACME](acme.md#internal-gateway).
2. Internal ACME. A site that runs an ACME-capable CA sets `pki.acme.server`, and cert-manager renews the gateway certificates against it. See [Internal ACME server](acme.md#internal-acme-server).
3. A subordinate CA. The site's PKI team signs a CSR for the cluster CA, so every certificate the cluster issues chains to the corporate root. See [Sign the cluster CA](private-ca.md#sign-the-cluster-ca).
4. A supplied certificate. The PKI team issues a wildcard certificate for each gateway domain, and the operator renews it by hand. See [Supplied certificates](supplied.md).
5. The generated CA. Core needs nothing from the site, and clients trust the gateway only after the CA's root is added to their trust stores. See [Cluster CA](private-ca.md).

The generated CA is the default because it works with no input. It is the right choice for an air-gapped site with no corporate PKI, and for pilots and labs.

## Behind the gateway

The gateway ends TLS for clients and forwards to the backend inside the cluster. On Cilium clusters outside workstation contexts, [WireGuard](../cni/cilium.md#encryption) encrypts that pod traffic between nodes. A backend that speaks TLS itself, such as Keycloak, gets a `BackendTLSPolicy` from its add-on that verifies it against the cluster CA. Neither needs a setting.

## Monitoring

With `telemetry.metrics.enabled` (the default), Prometheus scrapes cert-manager, and an x509 exporter reads the `tls.crt` and `ca.crt` of every `kubernetes.io/tls` Secret. Two alerts fire from its metrics: `X509CertificateExpiringSoon` 30 days before a certificate expires, and `X509CertificateExpiring` 7 days before. They cover supplied certificates, which nothing renews, and the cluster CA, which cert-manager does not watch. `observability.enabled` adds a cert-manager dashboard.

## Operations

On docker-desktop and Colima, cert-manager's controller can restart after the host sleeps. It logs `clockHealth failed: the system clock is out of sync` with `Reason: Completed`. On wake, the VM's wall clock jumps forward while the controller's monotonic clock does not, and the restart resets it.

> [!NOTE]
> The restarts stop once the VM's clock settles.

## Configuration

This table lists every `values.yaml` key the PKI guides use.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.public_domain` | string | none | Domain of the `external` gateway. Core writes its zone on AWS, Azure, GCP, and Hetzner. See [DNS](../dns/index.md). |
| `dns.private_domain` | string | by platform | Domain of the `internal` gateway. SHOULD be a subdomain of `dns.public_domain`. |
| `email` | string | none | ACME account contact. Required when a gateway uses `public-acme`. |
| `gateway.<name>.tls.issuer` | string | inferred | `ca`, `acme`, or `selfsigned`. Ignored when `tls.cert` is set. |
| `gateway.<name>.tls.cert` | string | none | PEM certificate chain, leaf first. MUST cover `<domain>` and `*.<domain>`. |
| `gateway.<name>.tls.key` | string | none | PEM private key for `tls.cert`. |
| `pki.acme.server` | string | none | Directory URL of an internal ACME server. |
| `pki.acme.ca_bundle` | string | system roots | PEM CA that signs the ACME server's own TLS certificate. |
| `pki.acme.eab.key_id` | string | none | External account binding key ID. Set with `hmac_key`. |
| `pki.acme.eab.hmac_key` | string | none | External account binding HMAC key. Set with `key_id`. |
| `pki.ca.cert` | string | generated | PEM CA certificate chain. Alone, the signed CSR. With `key`, a CA you bring. |
| `pki.ca.key` | string | generated | PEM CA private key. Requires `cert`. |
| `pki.trusted_cas` | list | none | PEM roots added to the trust bundle and the API server's OIDC CA file. |
| `pki.public_issuer` | string | none | Deprecated. `selfsigned` acts as `gateway.external.tls.issuer: selfsigned`. |
| `pki.private_ca` | object | none | Deprecated. Read as `pki.ca` when that is unset. |
| `pki.enabled` | boolean | none | Deprecated and ignored. The cluster CA always runs. |
| `policies.enabled` | boolean | `true` | Installs the Kyverno policy that mounts the CA bundle into labeled pods. |

## Reference

- [kustomize/pki](../../../kustomize/pki)
- [kustomize/crds](../../../kustomize/crds)
- [kustomize/policy](../../../kustomize/policy)
- [kustomize/telemetry](../../../kustomize/telemetry)
- [terraform/pki/ca](../../../terraform/pki/ca)
