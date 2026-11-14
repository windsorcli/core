---
title: PKI
description: TLS certificates through cert-manager, from Let's Encrypt, an internal ACME server, the cluster CA, or a certificate the site supplies, with trust-manager to distribute the CA.
sidebar_order: 5
---

Each [gateway](../gateway/index.md) serves TLS. Before `my-app.example.com` answers over HTTPS, a CA must sign a certificate for it. In Windsor, *cert-manager* gets these certificates. cert-manager runs in each cluster. It issues the certificate for each gateway, and the internal certificates that some add-ons need.

The authority that signs a gateway certificate depends on what the site has. The site can have a public zone that Core can write, its own ACME server, or a corporate CA. It can also have none of these.

`values.yaml` states these facts, and Core selects all issuers from them. This example sets two domains and an ACME contact. The other PKI pages use the same example.

```yaml
dns:
  public_domain: example.com
  private_domain: int.example.com
email: ops@example.com
```

`dns.public_domain` gives the cluster an `external` gateway for `example.com`. `dns.private_domain` gives it an `internal` gateway for `int.example.com`. `email` is the contact that Let's Encrypt keeps on the account.

On AWS, both gateways get Let's Encrypt certificates. On metal, `internal` gets a certificate from the [cluster CA](private-ca.md). Each cluster runs the cluster CA. Each cluster also runs *trust-manager*, the controller that distributes the CA to workloads that opt in.

## Issuers

cert-manager signs through an *issuer*. An issuer is a resource that names a certificate authority and how to connect to it. Core defines cluster-wide issuers as `ClusterIssuer` resources with fixed names. Add-ons refer to them by name. This table gives each issuer, what it signs with, and when it exists.

| Issuer | Signs with | Exists when |
|---|---|---|
| `public-acme` | [Let's Encrypt](acme.md), through DNS-01 in the public zone that Core writes. | A gateway uses it. |
| `private-acme` | The [internal ACME server](acme.md#internal-acme-server) in `pki.acme.server`. | A gateway uses it. |
| `public-selfsigned` | A self-signed certificate for each request. | A gateway uses it. Also on AWS, Azure, GCP, and Hetzner when no gateway uses `public-acme`, and always in dev mode. |
| `private` | The [cluster CA](private-ca.md). | Always. |

`private` also issues the certificates between CoreDNS and its etcd for [private DNS](../dns/private.md). It issues all other workload certificates that an add-on requests. The issuer of the gateways does not change this.

When the issuer of a gateway changes, cert-manager issues a new certificate into the same Secret. The gateway continues to read the same Secret name.

## Gateway certificates

Core selects the issuer for each gateway separately. It uses these rules, in this order:

1. A gateway with `gateway.<name>.https: false` has no HTTPS listener and no certificate.
2. A gateway with `gateway.<name>.tls.cert` serves that [supplied certificate](supplied.md) and uses no issuer.
3. A gateway with `gateway.<name>.tls.issuer` uses the issuer that it names.
4. All other gateways use the first row in this table where the condition is true.

| Gateway | Condition | Issuer |
|---|---|---|
| `external` | Core writes the public zone: `dns.public_domain` on AWS, Azure, GCP, or Hetzner, and `dns.public_zone` is `true` | `public-acme` |
| `external` | `pki.acme.server` is set | `private-acme` |
| `external` | dev mode | `public-selfsigned` |
| `external` | all other cases | none. Windsor rejects the configuration. |
| `internal` | `pki.acme.server` is set | `private-acme` |
| `internal` | `dns.private_domain` is a subdomain of `dns.public_domain`, and Core writes the public zone | `public-acme` |
| `internal` | all other cases | `private` |

The `internal` rows show why the private domain SHOULD be a [subdomain of the public domain](../dns/index.md#domains-and-gateways). Let's Encrypt validates a wildcard through a DNS-01 record in the public zone. For `int.example.com`, that record is in `example.com`, which Core already writes. The `internal` gateway then gets a certificate that all browsers trust. A private domain outside the public zone has no public location for the record.

`gateway.<name>.tls.issuer` has three values:

- `ca` uses `private`. Use it to keep internal hostnames out of Certificate Transparency logs.
- `acme` uses `pki.acme.server` or Let's Encrypt. Validation fails when neither is available to that gateway.
- `selfsigned` uses `public-selfsigned`. It is for tests.

> [!NOTE]
> Browsers show a warning for each self-signed certificate, because each one is its own root.

The deprecated `pki.public_issuer: selfsigned` has the same effect as `gateway.external.tls.issuer: selfsigned`.

## Choosing a source on-prem

A cluster on metal, vSphere, Hyper-V, Incus, or Proxmox has more choices. Its clients are often managed devices that trust only the roots of the site. This list gives the options in order of preference. Each option needs more from the site than the next option. In return, clients need less work to trust the certificate.

1. Public ACME on a subdomain. Core writes the public zone, and `dns.private_domain` is under `dns.public_domain`. Both gateways get Let's Encrypt certificates, and no client needs a private root. Core writes public zones only on AWS, Azure, GCP, and Hetzner. An on-prem cluster cannot use this option yet. See [ACME](acme.md#internal-gateway).
2. Internal ACME. The site sets `pki.acme.server`, and cert-manager renews the gateway certificates from that server. The server must pre-authorize the gateway domains for the account. A server that challenges each order does not work yet. See [Internal ACME server](acme.md#internal-acme-server).
3. A subordinate CA. The PKI team of the site signs a CSR for the cluster CA. All certificates that the cluster issues then chain to the corporate root. See [Sign the cluster CA](private-ca.md#sign-the-cluster-ca).
4. A supplied certificate. The PKI team issues a wildcard certificate for each gateway domain. The operator renews it manually. See [Supplied certificates](supplied.md).
5. The generated CA. Core needs nothing from the site. Clients trust the gateway only after you add the root of the CA to their trust stores. See [Cluster CA](private-ca.md).

The generated CA is the default, because it works with no input. Use it at an air-gapped site with no corporate PKI, and for pilots and labs.

## Behind the gateway

The gateway ends TLS for clients and sends the request to the backend in the cluster. On Cilium clusters outside workstation contexts, [WireGuard](../cni/cilium.md#encryption) encrypts that pod traffic between nodes. Some backends use TLS themselves, for example Keycloak. The add-on of such a backend adds a `BackendTLSPolicy` that verifies the backend against the cluster CA. These two features need no setting.

## Monitoring

With `telemetry.metrics.enabled` (the default), Prometheus scrapes cert-manager. An x509 exporter reads `tls.crt` and `ca.crt` from each `kubernetes.io/tls` Secret. Two alerts use its metrics:

- `X509CertificateExpiringSoon` fires 30 days before a certificate expires.
- `X509CertificateExpiring` fires 7 days before a certificate expires.

The alerts cover supplied certificates, which nothing renews. They also cover the cluster CA, which cert-manager does not monitor. `observability.enabled` adds a cert-manager dashboard.

## Operations

On docker-desktop and Colima, the cert-manager controller can restart after the host sleeps. It logs `clockHealth failed: the system clock is out of sync` with `Reason: Completed`. When the host wakes, the wall clock of the VM jumps forward. The monotonic clock of the controller does not jump. The restart resets the clock of the controller.

> [!NOTE]
> The restarts stop when the clock of the VM is stable.

## Configuration

This table gives all the `values.yaml` keys that the PKI guides use.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dns.public_domain` | string | none | Domain of the `external` gateway. Core writes its zone on AWS, Azure, GCP, and Hetzner. See [DNS](../dns/index.md). |
| `dns.private_domain` | string | by platform | Domain of the `internal` gateway. SHOULD be a subdomain of `dns.public_domain`. |
| `email` | string | none | ACME account contact. Required when a gateway uses `public-acme`. |
| `gateway.<name>.https` | boolean | `true` | Serves `web-https`. With `false`, the gateway has no certificate. |
| `gateway.<name>.tls.issuer` | string | inferred | `ca`, `acme`, or `selfsigned`. Ignored when `tls.cert` is set. |
| `gateway.<name>.tls.cert` | string | none | PEM certificate chain, leaf first. MUST cover `<domain>` and `*.<domain>`. |
| `gateway.<name>.tls.key` | string | none | PEM private key for `tls.cert`. |
| `pki.acme.server` | string | none | Directory URL of an internal ACME server. |
| `pki.acme.ca_bundle` | string | system roots | PEM CA that signs the TLS certificate of the ACME server. |
| `pki.acme.eab.key_id` | string | none | External account binding key ID. Set it with `hmac_key`. |
| `pki.acme.eab.hmac_key` | string | none | External account binding HMAC key. Set it with `key_id`. |
| `pki.ca.cert` | string | generated | PEM CA certificate chain. Alone, the signed CSR. With `key`, a CA that you supply. |
| `pki.ca.key` | string | generated | PEM CA private key. Requires `cert`. |
| `pki.trusted_cas` | list | none | PEM roots added to the trust bundle and to the OIDC CA file of the API server. |
| `pki.public_issuer` | string | none | Deprecated. `selfsigned` has the same effect as `gateway.external.tls.issuer: selfsigned`. |
| `pki.private_ca` | object | none | Deprecated. Read as `pki.ca` when `pki.ca` is not set. |
| `pki.enabled` | boolean | none | Deprecated and ignored. The cluster CA always runs. |
| `policies.enabled` | boolean | `true` | Installs the Kyverno policy that mounts the CA bundle into labeled pods. |

## Reference

- [kustomize/pki](../../../kustomize/pki)
- [kustomize/crds](../../../kustomize/crds)
- [kustomize/policy](../../../kustomize/policy)
- [kustomize/telemetry](../../../kustomize/telemetry)
- [terraform/pki/ca](../../../terraform/pki/ca)
