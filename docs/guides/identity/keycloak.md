---
title: Keycloak
description: Hosted Keycloak as the cluster identity provider, running in-cluster with its own Postgres database.
---

Keycloak is the default identity provider. When identity is enabled, Core runs Keycloak in the cluster, and Grafana, kubectl, and other add-ons with SSO support sign in through it. This page assumes the terms *identity provider*, *consumer*, *client*, and *realm* from the [Identity](index.md) overview, and its examples use that page's `example.com` context.

## Turn it on

A cluster without an identity provider has nothing for its consumers to sign in through. The smallest `values.yaml` that runs one is a single key:

```yaml
identity:
  enabled: true
```

`identity.driver` defaults to `keycloak`, so this is enough. Core installs the Keycloak operator, a `Keycloak` server and a dedicated CloudNativePG `Cluster` named `keycloak-db`, all in the `system-identity` namespace. The operator's CRDs come from the vendored `keycloak-26.8.0` CRD layer.

Keycloak stores its data in Postgres, so `identity.enabled` also turns on `database.postgres.enabled` unless you set it to `false` explicitly. [CloudNativePG](../database/cloudnativepg.md) describes that database add-on.

> [!WARNING]
> Setting `database.postgres.enabled: false` alongside `identity.enabled` leaves Keycloak without a database.

## Where Keycloak is published

Users reach the login page through the gateway. Core publishes it at `keycloak.<domain>`, where `<domain>` is `dns.public_domain`, or `dns.private_domain` if no public domain is set; in the example context that is `keycloak.example.com`. The login binds to the `external` gateway when one exists and to `internal` otherwise, and the `external` route exposes only the paths a login needs. The admin console is published at `keycloak-admin.<dns.private_domain>`, here `keycloak-admin.example.internal`, on the `internal` gateway only. On docker-desktop the URL includes the gateway's host port, `:8443` for `internal` and `:8444` for `external`.

A plain NodePort or a fixed production hostname needs a URL the derivation can't produce. Set it directly with `identity.keycloak.hostname`:

```yaml
identity:
  keycloak:
    hostname: https://sso.example.com
```

Without a gateway the server still runs, but nothing outside the cluster can reach it. Use `kubectl port-forward` to the `keycloak-service` Service in `system-identity`.

## Dev mode logins

A fresh realm has no users, so SSO has nobody to sign in. With `dev: true`, Core seeds the accounts in the table below so SSO works without any setup. None of them exist outside dev.

| Account | Username | Password | Access |
|---|---|---|---|
| Keycloak console | `admin` | `admin-password` | Keycloak console admin |
| SSO admin | `dev-admin` | `admin-password` | Member of the admin group (`platform-admins` by default): Grafana Admin, and `cluster-admin` when kubectl OIDC is on |
| SSO viewer | `dev-viewer` | `viewer-password` | Grafana Viewer, no Kubernetes permissions |

The console admin and `dev-admin` share a password. Setting `identity.keycloak.admin.password` changes both.

## Admin console

Configuring Keycloak by hand, such as adding users, needs an admin login. In dev mode it is the console account in [Dev mode logins](#dev-mode-logins). Outside dev, the operator generates a temporary admin on first boot and stores it in the `keycloak-initial-admin` secret. These commands read its username and password:

```sh
windsor exec -- kubectl -n system-identity get secret keycloak-initial-admin \
  -o jsonpath='{.data.username}' | base64 -d
windsor exec -- kubectl -n system-identity get secret keycloak-initial-admin \
  -o jsonpath='{.data.password}' | base64 -d
```

To set a known admin in any environment, provide the credentials under `identity.keycloak.admin`:

```yaml
identity:
  keycloak:
    admin:
      username: admin
      password: ${secret("MyVault", "keycloak-admin", "password")}
```

> [!IMPORTANT]
> The operator applies `identity.keycloak.admin` only when it first creates the server. Changing it later does not rotate the existing admin.

## Platform realm

Core imports a `platform` realm for consumers, so applications stay out of Keycloak's `master` realm. The realm enforces TLS for external requests, brute-force detection, and a password policy of at least 12 characters that cannot match the username or email. Access tokens last 5 minutes, and SSO sessions expire after 30 minutes idle or 10 hours total.

The realm also has a `platform-admins` group mapped to the realm-management `realm-admin` role. Core creates the group but not its members; add them in the console. In dev mode the realm also has the two sign-in users from [Dev mode logins](#dev-mode-logins). To give the realm another name, set `identity.keycloak.realm`:

```yaml
identity:
  keycloak:
    realm: corp
```

The import runs once. Later changes happen in the console, or by recreating the `KeycloakRealmImport`, and Git changes to the realm are not applied. One exception: adding a consumer that needs a new client, such as turning on Grafana SSO after the fact, re-imports the realm.

## Grafana single sign-on

Grafana's local login is one more set of credentials to manage. Once identity is enabled, Grafana signs in through Keycloak with no further configuration:

```yaml
identity:
  enabled: true
observability:
  enabled: true
```

Opening Grafana sends the browser to Keycloak to log in, then back to Grafana. Core registers the `grafana` client in the platform realm for you. It is a public PKCE client, so there is no secret to create or store. Grafana redirects the browser to Keycloak's public URL, so the gateway MUST be enabled. Set `observability.grafana.sso: false` to keep Grafana's local login instead.

### Who gets which role

Grafana takes a user's role from their Keycloak groups. Members of `platform-admins` become Admin, and everyone else becomes Viewer. Core creates that group empty, and outside dev the realm has no users. To give someone admin access, create the user in the Keycloak console, or connect Keycloak to your directory, and add them to `platform-admins`.

In dev mode `dev-admin` is already in the group and `dev-viewer` is not, and Grafana skips its login page and goes straight to Keycloak.

To map roles from a different group, set `observability.grafana.role_attribute_path`. Group names in the token include a leading slash:

```yaml
observability:
  grafana:
    role_attribute_path: "contains(groups[*], '/grafana-admins') && 'Admin' || 'Viewer'"
```

## kubectl single sign-on

kubectl can sign in through Keycloak as well. Setting `cluster.oidc.enabled: true` makes the Kubernetes API server accept Keycloak tokens:

```yaml
identity:
  enabled: true
cluster:
  oidc:
    enabled: true
```

The setting patches the Talos machine config with `--oidc-*` flags. Core fills in `issuer_url` and `client_id` from the platform realm and registers a public `kubernetes` PKCE client. The client accepts redirects to `http://localhost:8000` and `http://localhost:18000`, so a kubectl plugin such as `kubelogin` works with its default settings. The API server also trusts the cluster CA when it verifies tokens. `cluster.oidc.username_claim` (default `sub`) and `cluster.oidc.groups_claim` (default `groups`) change which token claims Kubernetes uses.

The API server fetches the issuer's keys itself, so the gateway MUST be enabled. Otherwise set `cluster.oidc.issuer_url` explicitly.

OIDC only authenticates users and grants no permissions. Outside dev you bind `platform-admins`, or another claim, to a `ClusterRoleBinding` yourself. In dev mode Core binds `platform-admins` to `cluster-admin`, so `dev-admin` can do something after logging in.

> [!IMPORTANT]
> kubectl single sign-on works only on Talos clusters. That is every platform except AWS, Azure, and GCP unless you override `cluster.driver`.

On EKS, AKS, and GKE the setting does nothing and nothing warns about it. Those control planes accept no API server flags, and their platform facets never read `cluster.oidc`. Use the cloud's own mechanism there, such as EKS access entries or Microsoft Entra. Hosted Keycloak and Grafana SSO work on every platform.

## Server image

By default the stock Keycloak image runs its build step every time a pod starts. For faster startup, build an optimized image with `kc.sh build --db=postgres`, push it to your registry, and reference it by digest in `identity.keycloak.image`:

```yaml
identity:
  keycloak:
    image: registry.example.com/keycloak-optimized:26.8.0@sha256:<digest>
```

Core assumes a custom image is pre-built, so the operator starts it with `--optimized`. The image MUST be pinned by digest, because `system-identity` is policy-managed and rejects tags alone.

## High availability

Under any topology other than `ha`, Keycloak and its database each run as a single instance. With `topology: ha`, Keycloak runs two replicas clustered through Infinispan, and the database grows from one Postgres instance to three with automatic failover. Both use hard pod anti-affinity, so the cluster needs at least two schedulable nodes for Keycloak and three for the database.

## Monitoring

When `telemetry.metrics.enabled` is true (the default), Keycloak exposes server and user-event metrics on its management port, and Prometheus scrapes them through the operator's ServiceMonitor. The `keycloak-db` cluster gets its own PodMonitor. `observability.enabled` adds an identity dashboard, and `telemetry.alerts.enabled` (default true) adds identity alert rules.

## Under the hood

Keycloak has no first-party Helm chart. Core vendors the operator's Deployment and RBAC unchanged, and the matching CRDs come in through the CRD layer from the same upstream release. The diagram below shows how Flux, the operator, the server, and its database fit together in `system-identity`, and how users reach the server through the gateway.

```mermaid
flowchart LR
  flux[Flux]
  users[Browser and OIDC clients]

  subgraph systemidentity[system-identity]
    operator[Keycloak operator]
    keycloak_cr[Keycloak CR]
    keycloak_sts[Keycloak StatefulSet]
    realm[KeycloakRealmImport]
    pg[CNPG Cluster<br/>keycloak-db]
  end

  gateway[Gateway<br/>system-gateway]

  flux ==> operator
  operator -->|reconciles| keycloak_cr
  keycloak_cr -->|creates| keycloak_sts
  operator -->|applies| realm
  keycloak_sts -->|JDBC over TLS| pg
  users -->|HTTPS| gateway
  gateway -->|HTTP| keycloak_sts
  classDef k8s fill:#326CE533,stroke:#326CE5
  classDef app fill:#2E7D3233,stroke:#2E7D32
  class flux,operator,keycloak_cr,keycloak_sts,realm,pg,gateway k8s
  class users app
```

TLS ends at the gateway. Keycloak serves plain HTTP inside the cluster and reads the proxy's forwarded headers for the external scheme and host. The gateway redirects plain HTTP to HTTPS, and with the Cilium gateway driver a network policy limits Keycloak's ingress to the gateway proxy.

Keycloak connects to Postgres with `sslmode=verify-full` against CloudNativePG's generated CA. Grafana and kubectl are public PKCE clients, so there are no client secrets to keep out of Git. A public client cannot prove the Grafana server's identity to Keycloak. Instead, the PKCE verifier ties each authorization code to the login that requested it.

## Configuration

The table below lists the `identity` keys this driver reads, with their defaults.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `identity.enabled` | boolean | `false` | Enable the cluster identity provider. |
| `identity.driver` | string | `keycloak` | `keycloak` hosts one in the cluster. `oidc` uses an [external issuer](oidc.md). |
| `identity.display_name` | string | `SSO` | Login button label consumers show, such as "Sign in with \<name\>". |
| `identity.admin_group` | string | `platform-admins` | Group whose members are administrators in every consumer. Core creates it in the realm. |
| `identity.keycloak.realm` | string | `platform` | Realm consumers target; also the issuer path. |
| `identity.keycloak.hostname` | string | derived | External hostname or base URL. Defaults to `keycloak.<domain>`. |
| `identity.keycloak.image` | string | stock image | Pre-built optimized server image, pinned by digest. |
| `identity.keycloak.admin.username` | string | `admin` | Bootstrap admin username. Applied only at first creation. |
| `identity.keycloak.admin.password` | string | none | Bootstrap admin password, also the `dev-admin` password in dev. Accepts `${secret(...)}`. Unset means a dev default, or the operator's temporary admin. |

## Reference

- [kustomize/identity](../../../kustomize/identity)
- [kustomize/crds](../../../kustomize/crds)
- [kustomize/database](../../../kustomize/database)
- [kustomize/gateway](../../../kustomize/gateway)
- [kustomize/observability](../../../kustomize/observability)
- [kustomize/telemetry](../../../kustomize/telemetry)
