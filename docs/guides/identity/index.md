---
title: Identity
description: Cluster single sign-on through a hosted Keycloak or an external OIDC provider.
sidebar_order: 1
---

Without single sign-on, each service in the cluster keeps its own logins, so an operator who uses Grafana and kubectl holds two separate sets of credentials. The core blueprint can give the cluster one *identity provider*, an OpenID Connect (OIDC) service that signs users in and issues tokens the other services accept. The services that sign in through it are its *consumers*.

The smallest configuration that turns it on goes in a context's `values.yaml`:

```yaml
identity:
  enabled: true
  driver: keycloak   # keycloak (default) or oidc
  display_name: SSO  # login button label
```

`identity.enabled` switches single sign-on on for the whole cluster. `identity.driver` picks where the identity provider lives: the default, [Keycloak](keycloak.md), runs inside the cluster, and [`oidc`](oidc.md) points the consumers at an external provider you already operate. `identity.display_name` is the label consumers put on their login button. The table below lists what Core deploys for each driver.

| `identity.driver` | What Core does |
|---|---|
| [`keycloak`](keycloak.md) | Runs Keycloak, its own Postgres database, and a `platform` realm in the cluster. |
| [`oidc`](oidc.md) | Deploys nothing. Uses the external provider at `identity.oidc.issuer`. |

The pages in this category share one example context, with `dns.public_domain: example.com` and `dns.private_domain: example.internal`. With the `keycloak` driver, that context's login page is `keycloak.example.com`. The `oidc` examples use an external issuer at `https://sso.example.com/realms/platform`.

## Consumers

A consumer signs users in through a *client*, an entry at the identity provider with an ID and the redirect URIs the provider may send a user back to. Grafana and kubectl can sign in through the cluster login, and each has its own setting. With `keycloak`, clients live in a *realm*, the Keycloak container for users, groups, and clients; Core names it `platform`. The table below lists each consumer's setting and who creates its client under each driver.

| Consumer | Setting | With `keycloak` | With `oidc` |
|---|---|---|---|
| Grafana | `observability.grafana.sso`, on by default when identity is enabled | Core creates a public PKCE client named `grafana` in the platform realm. | You register `grafana` at your provider as a public PKCE client, or as a confidential client with `observability.grafana.client_secret`. |
| kubectl | `cluster.oidc.enabled`, Talos clusters only | Core infers the issuer and creates a public PKCE client named `kubernetes`. | Core infers the issuer from `identity.oidc.issuer`. You register the client and set `cluster.oidc.client_id`. |

Both clients are *public PKCE clients*. PKCE (Proof Key for Code Exchange) checks each login without a shared secret, so by default there is no client secret to manage. [Grafana single sign-on](keycloak.md#grafana-single-sign-on) and [kubectl single sign-on](keycloak.md#kubectl-single-sign-on) cover each consumer in detail.

## Requirements

Windsor rejects these combinations when it validates the configuration:

- Grafana SSO with `keycloak` needs the gateway enabled, because the browser is redirected to Keycloak's public URL.
- kubectl OIDC with `keycloak` needs the gateway enabled, or an explicit `cluster.oidc.issuer_url`.
- Explicitly setting `observability.grafana.sso: true` needs `identity.enabled: true`.
