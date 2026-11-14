---
title: Supplied certificates
description: A gateway certificate issued by the PKI team of the site, served in place of an issued one, with the corporate root added to the cluster trust bundle.
---

Many PKI teams issue only leaf certificates. The team gets a request through a ticket or web enrollment. It gives back a certificate file and its key, valid for one or two years. A gateway can serve such a certificate directly. This page uses the gateway terms from [Gateway](../gateway/index.md) and the issuer terms from [PKI](index.md).

## Serve the certificate

This `values.yaml` gives the `internal` gateway a wildcard certificate for `int.example.com` from a secret store:

```yaml
gateway:
  internal:
    tls:
      cert: ${secret("vault", "k8s-wildcard", "chain")}
      key: ${secret("vault", "k8s-wildcard", "key")}
```

`gateway.internal.tls.cert` holds the PEM chain. The leaf is first, and its intermediates follow it. `gateway.internal.tls.key` holds the private key of the leaf. You MUST set both keys. Windsor rejects a configuration with only one. The `external` gateway uses the same keys under `gateway.external.tls`.

Core puts the certificate and key in a `kubernetes.io/tls` Secret in `system-gateway`. The Secret is `internal-supplied-tls` or `external-supplied-tls`. Core makes no cert-manager `Certificate` for that gateway. A supplied certificate takes priority over all issuers, including an issuer in `gateway.<name>.tls.issuer`.

> [!IMPORTANT]
> The certificate MUST cover `<domain>` and `*.<domain>`, in this example `int.example.com` and `*.int.example.com`. The listener of the gateway serves all routes under the domain. Windsor cannot check the names in the certificate before it applies.

A gateway that exists only for [ListenerSets](../gateway/index.md#a-gateway-without-a-domain) has no domain. If it serves `web-https`, it MUST have a supplied certificate.

## Renew it

Nothing renews a supplied certificate. When the PKI team issues a new certificate, update the secret value and run `windsor apply`. With `telemetry.metrics.enabled`, the [expiry alerts](index.md#monitoring) fire 30 days and 7 days before the certificate expires.

## Trust the corporate root

A chain from a PKI team usually ends at an intermediate. Browsers on managed devices already have the corporate root. Pods in the cluster do not have it. A pod that calls `https://grafana.int.example.com` then fails TLS. `pki.trusted_cas` adds the root:

```yaml
pki:
  trusted_cas:
    - ${secret("vault", "corp-root", "cert")}
```

Each entry is a PEM root certificate. Core adds the entries to the `private-ca` trust bundle that trust-manager distributes. See [Trust the CA in workloads](private-ca.md#trust-the-ca-in-workloads). With `cluster.oidc.enabled`, Talos also adds them to the OIDC CA file of the API server. The API server then trusts a Keycloak behind the supplied certificate. The same list also covers a TLS-inspecting proxy, or a registry with a certificate from a corporate root.

## Reference

- [kustomize/gateway](../../../kustomize/gateway)
- [kustomize/pki/resources/private-issuer/ca/trusted-cas](../../../kustomize/pki/resources/private-issuer/ca/trusted-cas)
- [kustomize/telemetry](../../../kustomize/telemetry)
