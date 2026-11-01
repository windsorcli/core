---
title: Identity
description: Cluster single sign-on through a hosted Keycloak or an external OIDC provider.
sidebar_order: 1
---

The core blueprint supports single sign-on for the cluster. The default provider is [Keycloak](keycloak.md), hosted in the cluster. An external [OIDC provider](oidc.md) can be used instead. The following config can be placed in a context's `values.yaml` file to enable it.

```yaml
identity:
  enabled: true
  driver: keycloak   # keycloak (default) or oidc
  display_name: SSO  # login button label
```

| `identity.driver` | What Core does |
|---|---|
| [`keycloak`](keycloak.md) | Runs Keycloak, its own Postgres database, and a `platform` realm in the cluster. |
| [`oidc`](oidc.md) | Deploys nothing. Uses the external provider at `identity.oidc.issuer`. |

## Consumers

Grafana and kubectl can sign in through the cluster login. Each has its own setting:

| Consumer | Setting | With `keycloak` | With `oidc` |
|---|---|---|---|
| Grafana | `observability.grafana.sso`, on by default when identity is enabled | Core creates a public PKCE client named `grafana` in the platform realm. | You register `grafana` at your provider as a public PKCE client, or as a confidential client with `observability.grafana.client_secret`. |
| kubectl | `cluster.oidc.enabled`, Talos clusters only | Core infers the issuer and creates a public PKCE client named `kubernetes`. | Core infers the issuer from `identity.oidc.issuer`. You register the client and set `cluster.oidc.client_id`. |

Both clients use PKCE, so by default there is no client secret to manage. See [Grafana single sign-on](keycloak.md#grafana-single-sign-on) and [kubectl single sign-on](keycloak.md#kubectl-single-sign-on) for the details.

## Requirements

Windsor rejects these combinations when it validates the configuration:

- Grafana SSO with `keycloak` needs the gateway enabled, because the browser is redirected to Keycloak's public URL.
- kubectl OIDC with `keycloak` needs the gateway enabled, or an explicit `cluster.oidc.issuer_url`.
- Explicitly setting `observability.grafana.sso: true` needs `identity.enabled: true`.
