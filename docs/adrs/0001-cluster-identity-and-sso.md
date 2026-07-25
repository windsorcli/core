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

Keycloak mints a secret for any confidential client that declares none, so a client's
secret can be read back over the admin API rather than supplied out of band or cloned.

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

### 3. Client registration: patch the client into the realm import

- **`driver: keycloak`** — each opted-in consumer patches its OIDC client into the
  platform `KeycloakRealmImport` from a per-consumer folder under `clients/`. This is
  the **stable v2beta1** path (the same realm import that ships the baseline). The
  realm's default groups scope carries `platform-admins` into tokens for role mapping.
- **`driver: oidc`** — no in-cluster client. The client is registered on the external
  IdP out of band; the consumer supplies `client_id` + `client_secret`.

The v2alpha1 `KeycloakOIDCClient` CRD was tried first and abandoned: it needs the
preview `client-admin-api:v2` server feature **and** a manually bootstrapped admin
service-account (a `<cr-name>-admin` secret with a master-realm client's
`client-id`/`client-secret`) that the operator authenticates with. Too much
alpha-stage surface for a baseline; the realm import needs none of it. The cost is
that the realm import is one-shot — adding a client re-imports the realm.

### 4. Client secrets: Keycloak generates, a Job copies it out

- **`driver: keycloak`** — the realm-import client sets no secret, so Keycloak generates
  one for the confidential client. A one-shot Job (`clients/grafana`) reads it back over
  the stable admin REST API and writes it into the consumer's namespace as a Secret. No
  value is supplied and none lands in git; the secret is stable because the realm import
  runs with `--override=false`, so re-imports never regenerate it.
- **`driver: oidc`** — no realm to generate from. The consumer supplies `client_secret`
  (a literal or `${secret(...)}` ref) from the external provider, and the observability
  facet writes it into Grafana's namespace.
- **Consumers wait, they do not misboot.** The client-secret env is `optional: false`,
  so the consumer pod blocks until the Secret lands.

The copy Job authenticates with the bootstrap admin (supplied, or the operator's
temporary one) and uses the stable admin REST API, not the alpha `client-admin-api:v2`
feature the v2alpha1 `KeycloakOIDCClient` CRD needs (decision 3). Two alternatives were
dropped: a Kyverno `generate`/`clone` policy (extra policy plus background-controller
RBAC to move a secret one Job can write directly), and a Terraform `random_password` →
`terraform_output` (secret-in-state, a TF stack on a kustomize-only addon).

The Keycloak console admin and, in dev, the seeded SSO admin user share one password
(`identity.keycloak.admin.password`, a dev default when unset), so a single override
sets both.

## Consequences

- **Migration.** `addons.keycloak.*` → `identity.*` across schema, the facet
  (`addon-keycloak.yaml` → an `identity` facet), tests, the identity stack README,
  and three memory notes. The blueprint is pre-release, so the key can move; a
  deprecation alias is an open question below.
- **Copy Job depends on admin creds.** The `clients/grafana` Job authenticates to the
  admin REST API with the bootstrap admin (supplied, or the operator's temporary one),
  and writes the Secret cross-namespace into the consumer's namespace (a Role there
  granted to the identity ServiceAccount). It waits for the realm client to exist, since
  the realm import runs in the same reconciliation.
- **No client CRD, no alpha feature.** Staying on the realm import avoids the v2alpha1
  `KeycloakOIDCClient` CRD and its `client-admin-api:v2` preview feature; the one-shot
  Job reads the generated secret over the stable admin API instead.
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
- **Keycloak generates, a Job copies.** Rejected: Kyverno clone (extra policy plus
  background-controller RBAC for a one-Job write), Terraform-in-state generation, and the
  v2alpha1 client CRD (alpha feature plus admin bootstrap).
- **Shared admin password.** One `identity.keycloak.admin.password` drives the console
  admin and the dev SSO admin user, with a dev default when unset.

## Open decisions

- **Endpoint derivation.** Grafana `generic_oauth` needs explicit auth/token/api
  URLs; deriving them from the issuer assumes the Keycloak/OIDC path convention.
  Fine for Keycloak (in-cluster and remote); non-Keycloak IdPs with other paths use
  the `identity.oidc.{auth,token,userinfo}_url` overrides.
- **Config can't reference computed config** (windsorcli/cli#3086) forces the endpoint
  derivation into the consumer's substitutions rather than `identity_effective`.

## Rollout

- **PR 2b (this work).** Hoist to `identity`; Grafana as the reference consumer
  (inferred SSO); Keycloak-generated client secret with a copy Job; realm baseline retained.
- **Fast-follow.** MinIO console, then gateway edge auth — each inferred the same way.
- **Later.** DB sizing/Pooler, realm reconciliation (keycloak-config-cli) — as in
  the existing plan.
