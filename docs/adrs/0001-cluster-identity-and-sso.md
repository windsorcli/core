---
title: Cluster identity and SSO
status: Proposed
---

# Cluster identity and SSO

## Status

Proposed. Supersedes the identity portions of
[docs/plans/keycloak-idp.md](../plans/keycloak-idp.md); that plan's PR 2 is
re-scoped around this model.

## Context

PR 1 (#2295) shipped a Keycloak server under `addons.keycloak`: the operator, a
`Keycloak` CR, its CloudNativePG database, and the gateway route. It stands up a
console and nothing else. PR 2a added the `platform` realm baseline (security
hardening, a `platform-admins` RBAC anchor, a groups client scope).

Wiring Grafana as the first SSO consumer surfaced that the original factoring is
wrong in three ways:

- **Identity is a cluster capability, not an addon.** "Who is the cluster's IdP?"
  is the same class of question as "what is the gateway?" or "what is DNS?" —
  cluster-wide, read by many. Burying it in `addons.keycloak` puts a vendor name
  in a top-level key (against the convention that top-level keys name a
  capability and the vendor is a `driver` value) and hides a shared concern
  inside one addon.
- **Consumers should not name Keycloak.** Grafana's `generic_oauth`, MinIO's
  OIDC, and gateway edge-auth all speak plain OIDC. They need an issuer, a client
  id, a client secret, and a role mapping — not a Keycloak-specific integration.
- **The IdP may be external or on another cluster.** A `KeycloakOIDCClient` can
  only target a `Keycloak` CR in its own namespace, so a remote or third-party
  IdP is out of reach by construction. That case must be expressible as "point at
  an issuer," not "run Keycloak here."

Kyverno is always present in the cluster (policy tier), which makes declarative,
self-healing secret provisioning available without an imperative Job.

## Decision

### 1. A top-level `identity` capability; drop `addons.keycloak`

`identity` is the one-stop home for the cluster IdP and the OIDC contract
consumers read.

```yaml
identity:
  enabled: true
  driver: keycloak        # keycloak (host in-cluster) | oidc (external / BYO)
  realm: platform         # realm/issuer path; default platform

  # driver: keycloak — hosting config (today's addons.keycloak fields)
  hostname: https://sso.example.com   # optional; derived otherwise
  image: ...                          # optional pre-built optimized image
  admin:
    username: admin
    password: ${secret(...)}

  # driver: oidc — point at an external issuer, no hosting
  issuer: https://sso.corp/realms/platform
```

- **`driver: keycloak`** deploys the existing identity stack (operator, `Keycloak`
  CR, CNPG, realm import, gateway route) and derives the effective issuer from
  `hostname`/domain + `realm`, exactly as today.
- **`driver: oidc`** hosts nothing. `issuer` is required and taken as-is; the
  remote/third-party IdP owns its realm and clients.

Either way, `identity` exposes an **effective issuer + realm** as the contract
every consumer ingests. This is the only thing core owes a consumer.

### 2. Consumers opt in with `sso`, provider-agnostic

Each SSO-capable addon gains an intent-level switch; the client specifics default
and only surface for overrides or the external case:

```yaml
addons:
  observability:
    grafana:
      sso: true                 # ingest identity.issuer; wire generic OIDC
      # optional:
      # client_id: grafana                       # default: the app name
      # client_secret: ${secret(...)}            # required for driver: oidc
      # role_attribute_path: "<jmespath>"        # default maps platform-admins → admin
```

A consumer never references Keycloak. It reads the effective issuer from
`identity` and contributes its own client id, secret, and role mapping.

### 3. Client registration follows the driver

- **`driver: keycloak`** — core registers a `KeycloakOIDCClient` per enabled
  consumer in `system-identity` (client id = the app name; v2alpha1 has no
  `clientId` field, so the resource name is the client id). The realm's groups
  scope carries `platform-admins` into tokens for role mapping.
- **`driver: oidc`** — no in-cluster client. The client is registered on the
  external IdP out of band; the consumer supplies `client_id` + `client_secret`.

### 4. Client secrets are declarative; dev fills a throwaway

The consumer's client secret must exist in the consumer's namespace, and (for
`driver: keycloak`) in `system-identity` where the `KeycloakOIDCClient` reads it.

- **Supplied.** The blueprint provides `client_secret` (a literal or a
  `${secret(...)}` ref), required whenever `sso` is on outside dev — an external IdP
  always owns it, and nothing is generated. It is materialized declaratively via
  facet `secrets:` blocks: one per namespace that needs it, both from the same
  reference, so the copies match. No controller, no Job.
- **Dev default.** In dev mode a throwaway `client_secret` is filled automatically,
  the same way dev defaults the Grafana admin password, so local SSO is zero-config.
- **Consumers wait, they do not misboot.** The client-secret env is
  `optional: false`, so the consumer pod blocks until the Secret exists and starts
  clean once it lands (kubelet-native retry).

Two alternatives were rejected. A one-shot generation Job (imperative kubectl,
cross-namespace RBAC) was removed in favor of the declarative supplied path plus the
dev default. Kyverno `generate`+`clone` is always available and fits *mirroring* a
secret across namespaces, but not *generating* a random one — `random()` under
`synchronize: true` churns the secret on every reconcile. A `clone` policy remains an
option if cross-namespace mirroring grows beyond one consumer.

## Consequences

- **Migration.** `addons.keycloak.*` → `identity.*` across schema, the facet
  (`addon-keycloak.yaml` → an `identity` facet), tests, the identity stack README,
  and three memory notes. The blueprint is pre-release, so the key can move; a
  deprecation alias is an open question below.
- **New Kyverno pattern.** First `generate`/`clone` policy; needs background
  controller secret RBAC and a policy test.
- **v2alpha1 client CRD risk** is unchanged — client CRDs are less stable than the
  server/realm CRDs; guard with tests and watch operator bumps.
- **Realm baseline (PR 2a) is unaffected** beyond gating rename; it already ships
  the groups scope this model relies on.

## Resolved decisions

- **Hard-cut, no alias.** `addons.keycloak` is removed outright; only `identity.*`
  is valid. The blueprint is pre-release, and in-repo contexts are updated in the
  same change.
- **Consumer switch is `sso: true`.** With optional `client_id` /
  `client_secret` / `role_attribute_path` overrides that surface only for the
  external-IdP case or non-default role mapping.

## Open decisions

- **Endpoint derivation.** Grafana `generic_oauth` needs explicit auth/token/api
  URLs; deriving them from the issuer assumes the Keycloak/OIDC path convention.
  Fine for Keycloak (in-cluster and remote); non-Keycloak IdPs with other paths
  need explicit endpoint overrides — defer until a real one appears.

## Rollout

- **PR 2b (this work).** Hoist to `identity`; Grafana as the reference consumer
  (`grafana.sso`); Kyverno generate/clone secret policy; realm baseline retained.
- **Fast-follow.** MinIO console, then gateway edge auth, each `sso: true`.
- **Later.** DB sizing/Pooler, realm reconciliation (keycloak-config-cli) — as in
  the existing plan.
