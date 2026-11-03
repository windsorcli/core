---
title: Supplied certificates
description: A gateway certificate issued by the site's PKI team, served in place of an issued one, with the corporate root added to the cluster trust bundle.
---

Many PKI teams issue only leaf certificates. They take a request through a ticket or web enrollment, and hand back a certificate file and its key, valid for a year or two. A gateway can serve such a certificate directly. This page assumes the gateway terms from [Gateway](../gateway/index.md) and the issuer terms from [PKI](index.md).

## Serve the certificate

This `values.yaml` gives the `internal` gateway a wildcard certificate for `int.example.com` from a secret store:

```yaml
gateway:
  internal:
    tls:
      cert: ${secret("vault", "k8s-wildcard", "chain")}
      key: ${secret("vault", "k8s-wildcard", "key")}
```

`gateway.internal.tls.cert` holds the PEM chain, with the leaf first and its intermediates after it. `gateway.internal.tls.key` holds the leaf's private key. You MUST set both, and Windsor rejects a configuration with only one. The `external` gateway takes the same keys under `gateway.external.tls`.

Core places the pair in a `kubernetes.io/tls` Secret in `system-gateway`, `internal-supplied-tls` or `external-supplied-tls`, and creates no cert-manager `Certificate` for that gateway. A supplied certificate wins over every issuer, including one set in `gateway.<name>.tls.issuer`.

> [!IMPORTANT]
> The certificate MUST cover both `<domain>` and `*.<domain>`, here `int.example.com` and `*.int.example.com`. The gateway's listener serves every route under the domain, and Windsor cannot check the certificate's names before it applies.

## Renew it

Nothing renews a supplied certificate. When the PKI team issues a new one, update the secret value and run `windsor apply`. With `telemetry.metrics.enabled`, the [expiry alerts](index.md#monitoring) fire 30 days and 7 days before the certificate expires.

## Trust the corporate root

A chain from a PKI team usually stops at an intermediate. Browsers on managed devices already hold the corporate root, but pods in the cluster do not, so a pod that calls `https://grafana.int.example.com` fails TLS. `pki.trusted_cas` adds the root:

```yaml
pki:
  trusted_cas:
    - ${secret("vault", "corp-root", "cert")}
```

Each entry is a PEM root certificate. Core adds them to the `private-ca` trust bundle that trust-manager distributes, as [Trust the CA in workloads](private-ca.md#trust-the-ca-in-workloads) describes. With `cluster.oidc.enabled`, Talos also appends them to the API server's OIDC CA file, so the API server trusts a Keycloak behind the supplied certificate. The same list covers a TLS-inspecting proxy or a registry that a corporate root signs.

## Reference

- [kustomize/gateway](../../../kustomize/gateway)
- [kustomize/pki/resources/private-issuer/ca/trusted-cas](../../../kustomize/pki/resources/private-issuer/ca/trusted-cas)
- [kustomize/telemetry](../../../kustomize/telemetry)
