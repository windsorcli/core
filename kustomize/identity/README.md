---
title: Identity add-on
description: Cluster identity provider (SSO) — hosted Keycloak or an external OIDC issuer.
---

# Identity

The cluster identity provider (SSO). `identity.driver: keycloak` (default) hosts
Keycloak in-cluster — the operator plus a single `Keycloak` server backed by its
own CloudNativePG database, reachable at `keycloak.${external_domain}` through the
shared gateway. `identity.driver: oidc` hosts nothing and points consumers at an
external issuer (`identity.issuer`).

Either way, `identity` exposes an effective issuer and realm that SSO consumers
read; consumers opt in with their own switch (e.g. `addons.observability.grafana.sso`)
and never name Keycloak. This page covers the hosted `keycloak` driver.

Keycloak has no first-party Helm chart, so the operator's Deployment/RBAC is
vendored verbatim (`install/keycloak-operator/operator.yaml`) and its CRDs are
vendored through the `crds:` layer (`kustomize/crds/keycloak-26.7.0`). Both come
from the same `keycloak-k8s-resources` release and are kept in lockstep by
`kustomize/crds/sources.yaml`. The operator does not manage its own CRDs.

## Architecture

```mermaid
flowchart LR
  flux[Flux helm/kustomize controllers]

  subgraph systemidentity[system-identity]
    operator_pod[Keycloak Operator Deployment]
    keycloak_cr[Keycloak CR]
    keycloak_sts[Keycloak StatefulSet<br/>provisioned by operator]
    keycloak_svc[Service<br/>keycloak-service :8080]
    pg_cluster[CNPG Cluster<br/>keycloak-db]
    pg_svc[Service<br/>keycloak-db-rw :5432]
  end

  gateway[[external Gateway<br/>system-gateway]]
  users[Browser / OIDC clients]

  flux ==> operator_pod
  operator_pod -.watches.-> keycloak_cr
  keycloak_cr -.creates.-> keycloak_sts
  keycloak_sts --> keycloak_svc
  keycloak_sts -->|JDBC / TLS| pg_svc
  pg_svc --- pg_cluster
  users -->|HTTPS| gateway
  gateway -->|HTTP| keycloak_svc
```

TLS terminates at the gateway; Keycloak serves plain HTTP internally and trusts
the proxy's `X-Forwarded-*` headers for the external scheme and host.

## Recipes

### Reach the admin console

The operator generates a temporary admin in the `keycloak-initial-admin` secret
on first boot:

```sh
windsor exec -- kubectl -n system-identity get secret keycloak-initial-admin \
  -o jsonpath='{.data.username}' | base64 -d
windsor exec -- kubectl -n system-identity get secret keycloak-initial-admin \
  -o jsonpath='{.data.password}' | base64 -d
```

To seed a known admin instead of the generated one, set `identity.keycloak.admin`
(the password takes a `${secret(...)}` reference or a literal):

```yaml
identity:
  enabled: true
  keycloak:
    admin:
      username: admin
      password: ${secret("MyVault", "keycloak-admin", "password")}
```

The operator honors `bootstrapAdmin` only at initial cluster creation, so this
seeds the first admin — it does not rotate an existing one.

Open `https://keycloak.${external_domain}` and sign in. On docker-desktop the
gateway is forwarded to a non-standard host port (e.g.
`https://keycloak.<domain>:8443`); Keycloak resolves its own scheme/port from the
request, so links stay on that port.

### Hostname / base URL

Keycloak bakes its external URL into every redirect and issuer, and it can't infer
the gateway's external port (that lives outside the cluster; the proxy only forwards
a standard one). The facet derives the base URL from the domain and the gateway
exposure: `https://keycloak.<domain>` on loadbalancer/cloud (`:443`), and
`https://keycloak.<domain>:8443` on docker-desktop (its NodePort host-forward).

Override for anything else — a plain-NodePort Talos VM on `:30443`, or a fixed
canonical production URL:

```yaml
identity:
  enabled: true
  keycloak:
    hostname: https://sso.example.com
```

### Server image: stock (default) vs. optimized

By default the stock Keycloak image runs with `startOptimized: false`, so it runs
its build step at each boot (a one-time cost per pod start) against the Postgres
backend. For faster, production-grade startup, pre-build an optimized image
(`kc.sh build --db=postgres …`), push it digest-pinned to your registry, and set:

```yaml
identity:
  enabled: true
  keycloak:
    image: registry.example.com/keycloak-optimized:26.7.0@sha256:<digest>
```

A set `image` is assumed pre-built, so the operator starts it with `--optimized`.
It must be digest-pinned — `system-identity` is policy-managed (Kyverno
`require-image-digest`).

### High availability

`topology: ha` scales the stack out — Keycloak runs 2 replicas (the operator wires
Infinispan clustering across them) on a 3-instance Postgres cluster (primary +
replicas with automatic failover). `single-node` and `multi-node` keep both at 1.

```yaml
topology: ha
identity:
  enabled: true
```

### Platform realm

Enabling Keycloak also imports a `platform` realm (apps never live in `master`).
It ships a security baseline — `sslRequired: external`, brute-force detection, a
`length(12) and notUsername and notEmail` password policy, and short access-token
plus bounded SSO-session lifetimes — and a `platform-admins` group mapped to the
realm-management `realm-admin` role as the one place to grant realm administration.
Core creates the group; its members are deployment-specific and are not managed in
git.

Rename the realm to fit an existing naming convention:

```yaml
identity:
  enabled: true
  keycloak:
    realm: corp
```

The import is one-shot: the operator applies the realm once via
`KeycloakRealmImport`, so later edits happen in-console (or by recreating the CR),
not by continuous reconciliation.

### Grafana single sign-on

Opt a consumer into SSO and it authenticates against the platform realm. For a
hosted Keycloak, core registers the OIDC client and provisions its secret; Grafana
maps the `platform-admins` group to the Grafana Admin role:

```yaml
identity:
  enabled: true
addons:
  observability:
    enabled: true
    grafana:
      sso: true
```

Supply the client secret from a store instead of generating it (recommended for
production), and override the client id or role mapping if needed:

```yaml
addons:
  observability:
    grafana:
      sso: true
      client_secret: ${secret("MyVault", "grafana-oidc", "clientSecret")}
```

### External identity provider

Point the cluster at an issuer you already run — a remote Keycloak, or any OIDC
provider — instead of hosting one. Nothing is deployed in `system-identity`;
consumers read the external issuer and bring their own client credentials. The
login button label is `identity.display_name` (default `SSO`), and endpoints are
derived from the issuer's standard OIDC path — override them if the provider differs:

```yaml
identity:
  enabled: true
  driver: oidc
  issuer: https://sso.corp/realms/platform
  display_name: Acme SSO
  # auth_url / token_url / userinfo_url  # only if the provider's paths are non-standard
addons:
  observability:
    grafana:
      sso: true
      client_secret: ${secret("MyVault", "grafana-oidc", "clientSecret")}
```

### Declarative clients

Core registers a `KeycloakOIDCClient` per opted-in consumer (Grafana today; MinIO
and gateway edge-auth to follow). Consuming blueprints add their own clients to the
platform realm the same way — a `KeycloakOIDCClient` (or `KeycloakSAMLClient`) in
`system-identity` — reading the realm name from `identity.keycloak.realm`. No core
change needed. See [docs/adrs/0001-cluster-identity-and-sso.md](../../docs/adrs/0001-cluster-identity-and-sso.md).

## Security

- **Database in transit.** Keycloak connects to Postgres with `sslmode=verify-full`,
  importing CNPG's generated CA into its truststore, so the server certificate and the
  `keycloak-db-rw` hostname are verified (TLS 1.3). Postgres authenticates Keycloak by
  password over that channel.
- **Ingress is HTTPS-only.** The gateway 301-redirects plain HTTP, and the Keycloak
  route attaches to the HTTPS listener only. On the Cilium gateway driver,
  `keycloak/cilium` further restricts Keycloak ingress to the gateway proxy via
  CiliumNetworkPolicy.
- **Admin credentials.** The operator generates a temporary admin by default; supply
  your own via `identity.keycloak.admin` (see Recipes). `bootstrapAdmin` seeds the
  initial admin only, not a rotation path.
- **Realm baseline.** The platform realm enforces `sslRequired: external`, brute-force
  detection, and a `length(12) and notUsername and notEmail` password policy, with
  short access tokens and bounded SSO sessions. Realm administration is granted through
  the `platform-admins` group (`realm-admin`), not by handing out the master admin.
- **Client secrets.** SSO client secrets never land in git. Supply one from a store
  (`grafana.client_secret: ${secret(...)}`) and it is materialized only in the
  namespaces that consume it; otherwise a Job generates a random secret in-cluster.
  Consumer pods use `optional: false` and wait for the Secret rather than start
  misconfigured.
- **Images.** `system-identity` is policy-managed (Kyverno `require-image-digest`); the
  operator, server, and Postgres images are all digest-pinned.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Components

| Component | Enable when | Effect |
|---|---|---|
| `keycloak-operator` | `identity.driver == 'keycloak'` | Keycloak Operator (Deployment + RBAC) in `system-identity`, vendored verbatim from keycloak-k8s-resources. Reconciles `Keycloak` custom resources; installs no server by itself. CRDs are applied separately by the `crds:` layer. |
| `keycloak` | `identity.driver == 'keycloak'` | The `Keycloak` server CR and its CloudNativePG `Cluster`. Keycloak serves HTTP internally (TLS terminates at the gateway) and stores realms in the `keycloak` database. |
| `keycloak/realm` | `identity.driver == 'keycloak'` | One-shot `KeycloakRealmImport` for the platform realm (name from `identity.keycloak.realm`, default `platform`): a security baseline (sslRequired, brute-force detection, password policy, token/session lifetimes), a `platform-admins` group mapped to `realm-admin`, and a groups client scope for role mapping. Consumers target this realm by name. |
| `keycloak/grafana` | `addons.observability.grafana.sso == true` | `KeycloakOIDCClient` registering Grafana in the platform realm (client id `grafana`; v2alpha1 derives it from the resource name). Reads the `grafana-oidc-client` Secret, materialized in this namespace from the supplied (or dev-default) client secret. |
| `keycloak/gateway` | `gateway.enabled == true` | HTTPRoute publishing `keycloak.${external_domain}` through the shared external Gateway to the operator-managed `keycloak-service`. |
| `keycloak/cilium` | `gateway.driver == 'cilium'` | CiliumNetworkPolicy restricting Keycloak ingress to the gateway proxy. Cilium-enforced, so gated on the Cilium gateway driver. |
| `keycloak/admin` | `identity.keycloak.admin.password` set | Points the `Keycloak` CR at the supplied `keycloak-bootstrap-admin` secret via `spec.bootstrapAdmin`, instead of the operator's auto-generated temporary admin. Honored only at initial cluster creation. |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `database` | `identity.driver == 'keycloak'` | Keycloak stores realm data in PostgreSQL; the CloudNativePG operator (database addon) must exist before its `Cluster` CR applies. |
| `gateway-resources` | `gateway.enabled == true` | The shared Gateway must exist before the Keycloak HTTPRoute attaches to it. |

<!-- END_KUSTOMIZE_DOCS -->

## See also

- [contexts/_template/facets/addon-identity.yaml](../../contexts/_template/facets/addon-identity.yaml) for the canonical wiring.
- [docs/adrs/0001-cluster-identity-and-sso.md](../../docs/adrs/0001-cluster-identity-and-sso.md) for the identity capability and SSO model.
- [kustomize/crds/sources.yaml](../crds/sources.yaml) for the vendored operator + CRD versions.
- Related add-ons: [database](../database/) (backing Postgres), [gateway](../gateway/) (ingress + TLS).
