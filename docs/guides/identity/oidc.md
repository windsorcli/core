---
title: External OIDC
description: An external OIDC provider as the cluster identity provider. Core deploys nothing into the cluster.
---

If your organization already runs an OIDC provider, the `oidc` driver makes it the cluster's identity provider, and Core deploys no identity provider of its own. This page assumes the terms *identity provider*, *consumer*, *client*, and *public PKCE client* from the [Identity](index.md) overview, and its examples use that page's `example.com` context.

## Turn it on

The consumers need to know where your provider lives. The smallest `values.yaml` that tells them sets the driver and the issuer:

```yaml
identity:
  enabled: true
  driver: oidc
  display_name: Acme SSO
  oidc:
    issuer: https://sso.example.com/realms/platform
```

`identity.oidc.issuer` is your provider's *issuer*, the base URL that identifies the provider in the tokens it issues. `display_name` is the label on the login button, such as "Sign in with Acme SSO".

> [!NOTE]
> Core does not check that the issuer is reachable or that your provider has the clients below. If a service redirects to a URL that does not exist, check the issuer first.

## Endpoints

A provider that doesn't follow Keycloak's URL layout breaks the default endpoints. Core builds the authorization, token, and userinfo URLs by adding Keycloak's paths to the issuer, for example `<issuer>/protocol/openid-connect/auth`. That works for Keycloak and for providers that copy its layout. For any other provider, set the endpoints explicitly:

```yaml
identity:
  oidc:
    issuer: https://login.example.com/oauth2/default
    auth_url: https://login.example.com/oauth2/default/v1/authorize
    token_url: https://login.example.com/oauth2/default/v1/token
    userinfo_url: https://login.example.com/oauth2/default/v1/userinfo
```

The browser is sent to `auth_url`. Services call `token_url` and `userinfo_url` from inside the cluster.

> [!IMPORTANT]
> `token_url` and `userinfo_url` MUST be reachable from the cluster network.

## Clients

With the `keycloak` driver Core registers clients itself. Here your provider is outside Core's reach, so each service that signs in through the cluster identity needs a client you register. Register them as public clients that use PKCE (S256). The table below lists the client ID, redirect URI, and enabling setting for each service.

| Service | Client ID | Redirect URI | Turned on by |
|---|---|---|---|
| Grafana | `grafana` | `https://grafana.<domain>/login/generic_oauth` | `observability.grafana.sso`, on by default when identity is enabled |
| kubectl | your choice, set as `cluster.oidc.client_id` | the one your kubectl plugin uses, such as `http://localhost:8000` for `kubelogin` | `cluster.oidc.enabled`, Talos clusters only |

Grafana is served on the `internal` gateway, so `<domain>` is `dns.private_domain`, and the example context's redirect URI is `https://grafana.example.internal/login/generic_oauth`. On docker-desktop the host includes `:8443`. There is no client secret to configure.

Services that pick a role from group membership read a `groups` claim, so your provider needs to include one in the token. Group names are matched as your provider emits them, and each service has its own role mapping, described under [Service settings](#service-settings).

## Public clients

A public client cannot prove a service's identity to your provider. The PKCE verifier ties each authorization code to the login that requested it, so a stolen code is not enough on its own. Some providers restrict or forbid public clients. For those, a service can be registered as a *confidential client* instead, which authenticates with a secret, where the service supports it. Grafana does, through `observability.grafana.client_secret`.

## Service settings

### Grafana

Grafana signs in through your provider once identity is enabled and its client exists. Set `observability.grafana.sso: false` to keep the local Grafana login instead.

By default Grafana maps a group named `/platform-admins` to Admin and everyone else to Viewer. A provider that names its groups differently, or puts them in another claim, needs its own mapping in `observability.grafana.role_attribute_path`:

```yaml
observability:
  grafana:
    role_attribute_path: "contains(groups[*], 'grafana-admins') && 'Admin' || 'Viewer'"
```

If your provider requires a confidential client, register Grafana that way and set the secret it issued:

```yaml
observability:
  grafana:
    client_secret: ${secret("MyVault", "grafana-oidc", "clientSecret")}
```

Grafana then sends the secret along with PKCE.

> [!NOTE]
> `observability.grafana.client_secret` applies only to the `oidc` driver.

### kubectl

`cluster.oidc.enabled: true` makes the Kubernetes API server accept tokens from your provider. It only works on Talos clusters. Core takes the issuer from `identity.oidc.issuer` but cannot guess the client, so name the one you registered in `cluster.oidc.client_id`:

```yaml
identity:
  enabled: true
  driver: oidc
  oidc:
    issuer: https://sso.example.com/realms/platform
cluster:
  oidc:
    enabled: true
    client_id: kubernetes
```

As with Keycloak, OIDC only authenticates users. Outside dev you grant permissions with a `ClusterRoleBinding` on a group or user from your provider. `cluster.oidc.username_claim` and `cluster.oidc.groups_claim` choose which token claims Kubernetes reads, and default to `sub` and `groups`.

## Configuration

The table below lists the keys this driver reads, with their defaults.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `identity.enabled` | boolean | `false` | Enable the cluster identity provider. |
| `identity.driver` | string | `keycloak` | Set to `oidc` for an external issuer. |
| `identity.display_name` | string | `SSO` | Login button label consumers show, such as "Sign in with \<name\>". |
| `identity.admin_group` | string | `platform-admins` | Group claim value that Grafana maps to its Admin role. Your provider MUST emit it. |
| `identity.oidc.issuer` | string | none | External OIDC issuer base URL. Set this for the driver. |
| `identity.oidc.auth_url` | string | issuer plus `/protocol/openid-connect/auth` | Authorization endpoint. |
| `identity.oidc.token_url` | string | issuer plus `/protocol/openid-connect/token` | Token endpoint. |
| `identity.oidc.userinfo_url` | string | issuer plus `/protocol/openid-connect/userinfo` | Userinfo endpoint. |
| `observability.grafana.client_secret` | string | none | Grafana's client secret, for providers that need a confidential client. Accepts `${secret(...)}`. Unset uses a public PKCE client. |

## Reference

Core installs no Kustomize components for this driver. The identity provider is yours to operate. Grafana reads the issuer through the observability add-on.

- [kustomize/observability](../../../kustomize/observability)
