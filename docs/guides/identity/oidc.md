---
title: OIDC
description: Point every consumer at an external OIDC issuer you already run — Windsor deploys nothing into the cluster.
---

`identity.driver: oidc` gives the cluster the same shared-login contract as [Keycloak](keycloak.md), but hosts nothing. Every consumer reads the issuer you already run and brings its own client credentials, since the external provider owns them.

## Turn it on

```yaml
identity:
  enabled: true
  driver: oidc
  display_name: Acme SSO
  oidc:
    issuer: https://sso.corp/realms/platform
observability:
  grafana:
    client_secret: ${secret("MyVault", "grafana-oidc", "clientSecret")}
```

With this driver, Windsor deploys nothing into `system-identity` — no operator, no CRDs, no Postgres. Consumers just see the effective issuer and realm; nothing downstream cares which driver is behind it, so [Let apps use it](keycloak.md#let-apps-use-it) and [kubectl over SSO](keycloak.md#kubectl-over-sso) both still apply, minus the parts specific to Windsor hosting Keycloak itself (there's no `identity.keycloak.grafana_client_secret` to pin — you set `client_secret` directly, as above, since the external provider issued it).

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `identity.display_name` | string | `SSO` | Login button label consumers show (e.g. "Sign in with \<name\>"). |
| `identity.oidc.issuer` | string | `—` | External OIDC issuer base URL. Required for this driver. |
| `identity.oidc.auth_url` | string | `—` | Override the OIDC authorization endpoint (defaults to the issuer's standard path). |
| `identity.oidc.token_url` | string | `—` | Override the OIDC token endpoint (defaults to the issuer's standard path). |
| `identity.oidc.userinfo_url` | string | `—` | Override the OIDC userinfo endpoint (defaults to the issuer's standard path). |

## Reference

Windsor installs no kustomize components for this driver — the identity provider is yours to operate and document. The one thing it does write is Grafana's OIDC client secret, into the observability add-on's own resources.

<!-- BEGIN_GUIDE_REFS -->

- [kustomize/observability](https://github.com/windsorcli/core/tree/main/kustomize/observability) on GitHub

<!-- END_GUIDE_REFS -->

- [Facets](https://www.windsorcli.dev/blueprints/facets) — how `identity.driver` selects between this and Keycloak
- [Expressions — secret()](https://www.windsorcli.dev/blueprints/expressions) — how `${secret(...)}` resolves
