---
title: Keycloak
description: Hosted Keycloak as the identity driver — the default, running in-cluster with its own Postgres database.
---

Keycloak gives the cluster one login every consumer can share, hosted entirely in-cluster. Turn it on once and Grafana, kubectl, and future add-ons authenticate against the same issuer instead of each carrying its own password.

## Turn it on

```yaml
identity:
  enabled: true
```

This is the default driver (`driver: keycloak`), so `enabled: true` alone is enough. It hosts the operator, a `Keycloak` server, and its own Postgres database, reachable at `keycloak.${external_domain}` through the shared gateway. A consumer with SSO support turns it on with its own switch and never has to name Keycloak directly:

```yaml
observability:
  enabled: true
  grafana:
    sso: true   # or omit: SSO is inferred once identity is enabled
```

In `dev` mode this needs no further setup. The platform realm seeds two users so you can see the role mapping work immediately: `dev-admin` / `admin-password` (admin everywhere) and `dev-viewer` / `viewer-password` (read-only). Neither exists outside dev.

## Let apps use it

A consumer opts in with its own flag rather than a global registry. Grafana is the one shipped today:

```yaml
identity:
  enabled: true
observability:
  enabled: true
  grafana:
    sso: true
```

Core registers a `grafana` OIDC client in the platform realm and pins its secret via `identity.keycloak.grafana_client_secret` (a dev default applies in dev; required otherwise). The client carries a mapper that puts the `platform-admins` group into the token, which Grafana maps to the Admin role. Override the mapping with `grafana.role_attribute_path`, or set `grafana.sso: false` to opt back out entirely.

## kubectl over SSO

`cluster.oidc.enabled: true` turns on OIDC login for the Kubernetes API server, **on Talos-driven platforms only** (Metal, Hetzner, Hyper-V, vSphere). It works by patching Talos's own machine config with `--oidc-*` flags on the apiserver, so it needs Windsor to control the control plane directly:

```yaml
identity:
  enabled: true
cluster:
  oidc:
    enabled: true
```

Windsor infers the issuer and a public PKCE client from the platform realm, so you don't need to set `issuer_url` or `client_id`. Pair this with a `kubectl` OIDC plugin such as `kubelogin`. OIDC only authenticates: it grants no RBAC by itself. Outside dev, bind `platform-admins` (or another realm claim) to a `ClusterRoleBinding` yourself. In `dev`, Windsor seeds that binding to `cluster-admin` so the seeded `dev-admin` user can do something after logging in.

**On AWS (EKS) and Azure (AKS), this flag does nothing.** Those are managed control planes. Windsor has no way to inject apiserver flags into them, and neither platform facet reads `cluster.oidc` at all. Setting it there is a silent no-op, not an error. Hosted Keycloak and Grafana SSO above still work fully on EKS/AKS. Only kube-apiserver-level `kubectl` login is Talos-only today. Reaching the same outcome on EKS or AKS means using each cloud's own native mechanism instead: EKS access entries/IAM, or Azure AD/Entra integration. Windsor doesn't wire either of those up yet.

## Under the hood

Keycloak has no first-party Helm chart, so its operator is vendored verbatim and its CRDs come in through the `crds:` layer, both from the same upstream release and kept in lockstep.

```mermaid
flowchart LR
  flux[Flux helm/kustomize controllers]

  subgraph systemidentity[system-identity]
    operator_pod[Keycloak Operator Deployment]
    keycloak_cr[Keycloak CR]
    keycloak_sts[Keycloak StatefulSet<br/>provisioned by operator]
    pg_cluster[CNPG Cluster<br/>keycloak-db]
  end

  gateway[[external Gateway<br/>system-gateway]]
  users[Browser / OIDC clients]

  flux ==> operator_pod
  operator_pod -.watches.-> keycloak_cr
  keycloak_cr -.creates.-> keycloak_sts
  keycloak_sts -->|JDBC / TLS| pg_cluster
  users -->|HTTPS| gateway
  gateway -->|HTTP| keycloak_sts
```

TLS terminates at the gateway. Keycloak serves plain HTTP internally and trusts the proxy's forwarded headers for the external scheme and host.

Enabling Keycloak also imports a `platform` realm. Apps never live in `master`. The import is one-shot: the operator applies it once, so later changes happen in-console (or by recreating the `Keycloak` resource), not by continuous reconciliation. The realm ships a security baseline (TLS required, brute-force detection, a 12-character password policy, short token and session lifetimes) and a `platform-admins` group as the one place to grant realm administration.

`topology: ha` scales the stack: Keycloak runs 2 replicas with clustering wired between them, on a 3-instance Postgres cluster with automatic failover. `single-node` and `multi-node` keep both at 1.

Database traffic is `sslmode=verify-full` against Postgres's own generated CA, ingress is HTTPS-only at the gateway, and every image in `system-identity` is digest-pinned under policy. Client secrets never land in git. `${secret(...)}` references resolve them at apply time, and consumer pods wait rather than start misconfigured.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `identity.display_name` | string | `SSO` | Login button label consumers show (e.g. "Sign in with \<name\>"). |
| `identity.keycloak.realm` | string | `platform` | Realm consumers target; also the issuer path. |
| `identity.keycloak.hostname` | string | `—` | External hostname or base URL for the hosted server; defaults to `keycloak.<domain>`. |
| `identity.keycloak.image` | string | `—` | Pre-built optimized server image, digest-pinned; defaults to the stock image built at boot. |
| `identity.keycloak.admin.username` | string | `admin` | Bootstrap admin username; seeds the initial admin only at first creation. |
| `identity.keycloak.admin.password` | string | `—` | Admin password for the console and, in dev, the SSO admin user. Supports `${secret(...)}` refs; unset means a dev default. |
| `identity.keycloak.grafana_client_secret` | string | `—` | Grafana's pinned OIDC client secret. Supports `${secret(...)}` refs; unset means a dev default. |

## Reference

<!-- BEGIN_GUIDE_REFS -->

- [kustomize/identity](https://github.com/windsorcli/core/tree/main/kustomize/identity) on GitHub
- [kustomize/observability](https://github.com/windsorcli/core/tree/main/kustomize/observability) on GitHub

<!-- END_GUIDE_REFS -->

- [Facets](https://www.windsorcli.dev/blueprints/facets), [Kustomize](https://www.windsorcli.dev/components/kustomize) — how add-ons like this compose into a blueprint
- [Expressions — secret()](https://www.windsorcli.dev/blueprints/expressions) — how `${secret(...)}` resolves
