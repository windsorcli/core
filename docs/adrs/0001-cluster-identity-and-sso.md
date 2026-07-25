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

Common fields sit flat; driver-specific config is grouped under `identity.keycloak`
(hosted) and `identity.oidc` (external), symmetric and self-documenting:

```yaml
identity:
  enabled: true
  driver: keycloak        # keycloak (host in-cluster) | oidc (external / BYO)
  display_name: SSO       # login button label

  # driver: keycloak — hosted server
  keycloak:
    realm: platform       # realm/issuer path; default platform
    hostname: https://sso.example.com   # optional; derived otherwise
    image: ...                          # optional pre-built optimized image
    admin: { username: admin, password: ${secret(...)} }

  # driver: oidc — external provider
  oidc:
    issuer: https://sso.corp/realms/platform
    # auth_url / token_url / userinfo_url — override only for non-standard paths
```

- **`driver: keycloak`** deploys the existing identity stack (operator, `Keycloak`
  CR, CNPG, realm import, gateway route) and derives the effective issuer from
  `keycloak.hostname`/domain + `keycloak.realm`, exactly as today.
- **`driver: oidc`** hosts nothing. `oidc.issuer` is required and taken as-is; the
  remote/third-party IdP owns its realm and clients.

Either way, `identity` exposes an **effective issuer, realm, display name, and
endpoints** (`identity_effective.*`) as the contract every consumer ingests.

### 2. Consumers infer SSO; provider-agnostic

SSO is inferred, not opted into per app: when `identity` and a capable consumer are
both enabled, the consumer wires up. No `sso: true`, no per-client schema — the
client id is the app name, the redirect derives from the app's URL, endpoints and
label come from `identity`, and role mapping defaults to platform-admins → admin.
Only escape hatches remain, all optional:

```yaml
addons:
  observability:
    grafana:
      # sso: false                                 # opt out
      # client_secret: ${secret(...)}              # required for driver: oidc only
      # role_attribute_path: "<jmespath>"          # override role mapping
```

A consumer never references Keycloak. The facets read `identity` and route the
values; a consumer contributes only what can't be inferred (its external client
secret, an opt-out, a role-mapping override).

### 3. Client registration follows the driver

- **`driver: keycloak`** — core registers a `KeycloakOIDCClient` per enabled
  consumer in `system-identity` (client id = the app name; v2alpha1 has no
  `clientId` field, so the resource name is the client id). The realm's groups
  scope carries `platform-admins` into tokens for role mapping.
- **`driver: oidc`** — no in-cluster client. The client is registered on the
  external IdP out of band; the consumer supplies `client_id` + `client_secret`.

### 4. Client secrets: generate with a Job, replicate with Kyverno

The client secret's source of truth lives in `system-identity` (where the
`KeycloakOIDCClient` reads it); consumers get a replicated copy.

- **Supplied or generated at the source.** If the blueprint provides `client_secret`
  (a literal or `${secret(...)}` ref) it is materialized into `system-identity` via a
  facet `secrets:` block. Otherwise a **one-shot Job** generates a random secret there
  — idempotent (it leaves an existing secret untouched) and single-namespace, so no
  cross-namespace RBAC. The `oidc` driver has no in-cluster client, so its consumer
  secret is supplied straight into the consumer namespace and must be provided.
- **Kyverno replicates outward.** A `ClusterPolicy` clones the `system-identity`
  secret into each consuming namespace and keeps it in sync. This is the split that
  makes Kyverno the right tool: it *clones an existing* secret (stable), it does not
  *generate a random one* (which would churn under `synchronize: true`). It needs a
  background-controller RBAC grant over secrets (an aggregated ClusterRole).
- **Consumers wait, they do not misboot.** The client-secret env is `optional: false`,
  so the consumer pod blocks until the replicated Secret lands (kubelet-native retry).

Generation belongs in a Job (one-shot, its natural fit); replication belongs in
Kyverno (declarative sync, its natural fit); `system-identity` is the hub that fans
one secret out to N consumers. A Terraform `random_password` → `terraform_output`
approach was prototyped and dropped: it put the secret in TF state and added a TF
stack to an otherwise kustomize-only addon.

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
- **Symmetric structure.** `identity.keycloak.*` (hosted) and `identity.oidc.*`
  (external); `enabled`/`driver`/`display_name` flat.
- **SSO is inferred, not opted into.** Both enabled → wired; optional `grafana.sso:
  false` opt-out, `client_secret` (oidc only), and `role_attribute_path` override.
- **Job generates, Kyverno replicates.** Rejected: Terraform-in-state generation, and
  Kyverno *generating* a random secret (churns under `synchronize`).

## Open decisions

- **Endpoint derivation.** Grafana `generic_oauth` needs explicit auth/token/api
  URLs; deriving them from the issuer assumes the Keycloak/OIDC path convention.
  Fine for Keycloak (in-cluster and remote); non-Keycloak IdPs with other paths use
  the `identity.oidc.{auth,token,userinfo}_url` overrides.
- **Config can't reference computed config** (windsorcli/cli#3086) forces the endpoint
  derivation into the consumer's substitutions rather than `identity_effective`.

## Rollout

- **PR 2b (this work).** Hoist to `identity`; Grafana as the reference consumer
  (inferred SSO); Job + Kyverno secret provisioning; realm baseline retained.
- **Fast-follow.** MinIO console, then gateway edge auth — each inferred the same way.
- **Later.** DB sizing/Pooler, realm reconciliation (keycloak-config-cli) — as in
  the existing plan.
