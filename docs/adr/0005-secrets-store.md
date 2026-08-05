---
title: "ADR-0005: secrets_store — self-hosted OpenBao, or an external Vault-API-compatible store"
description: "Closes core#2285. A top-level secrets_store capability with two drivers: openbao (self-hosted, single-cluster) and external (points a ClusterSecretStore at a Vault-API-compatible instance this cluster doesn't own — the shape a downstream fleet cluster needs to read from Windsor Manager's shared OpenBao). PKI is explicitly out of scope; that's fleet-only work."
---

# ADR-0005: secrets_store — self-hosted OpenBao, or an external Vault-API-compatible store

## Status

Proposed. Formalizes [core#2285](https://github.com/windsorcli/core/issues/2285),
extended with an `external` driver. Depends on
[ADR-0004](0004-external-secrets-operator.md). Depended on by
[ADR-0002](0002-cluster-secrets-management.md)'s `ExternalSecret`
materialization.

## Context

[core#2284](https://github.com/windsorcli/core/issues/2284) adds the ESO
controller. This addon adds the other half — a store for it to read from
— so a standalone cluster can be self-contained rather than depending on
an external SaaS secret manager: self-hosting the store is the whole
point for an airgapped or single-cluster install, which is a legitimate
consumer even though a fleet would run one shared instance.

**OpenBao rather than Vault, for the self-hosted case.** Vault relicensed
to BUSL 1.1 in August 2023; OpenBao is the Linux Foundation fork under
MPL 2.0, matching this repository's own license. Worth being a
deliberate choice: OpenBao is the driver core installs; HashiCorp Vault
is not offered as a second self-hosted chart to maintain under a license
misaligned with this repo's stance.

**But self-hosting is not the only shape this needs to support.** Windsor
Manager's fleet model (`manager` docs/adr/0003-secrets-and-pki.md) runs
one shared OpenBao on the management cluster and registers each
downstream cluster's own API server as a distinct Kubernetes-auth mount,
scoped to that cluster's secrets — no static credential crosses the
boundary. From a downstream cluster's own perspective (itself a `core`
blueprint), that means pointing its `ClusterSecretStore` at an instance
it does not run and did not install. Since ESO's `vault` provider type is
API-compatible with both OpenBao and HashiCorp Vault, the same "point at
an external instance" shape also covers an operator who already runs
their own Vault and wants nothing self-hosted at all — this ADR treats
both as the same driver.

**PKI is explicitly out of scope.** core#2285 draws this line itself: a
PKI secrets engine issuing certificates to other clusters overlaps with
the existing `pki` addon and `private_ca`, and mounting/operating one is
fleet-only work (Manager's own ADR-0003, decision 2). This addon installs
and configures a generic key/value-capable secrets store and its
`ClusterSecretStore`; it never mounts or manages a `pki` engine.

## Decision

### 1. A top-level `secrets_store` capability, two drivers

```yaml
secrets_store:
  enabled: false
  driver: openbao          # openbao | external
  openbao:
    # only consumed when driver: openbao
  external:
    url: ""                # Vault-API-compatible address (OpenBao or Vault)
    kubernetes_auth:
      mount_path: ""        # auth mount path this cluster was registered under
      role: ""              # role bound to that mount
```

Top-level, matching `identity`/`database`/`object_store`/`external_secrets`
— not nested under `addons:`.

### 2. `driver: openbao` — self-hosted, single cluster

A `flux:` system installing OpenBao (HA gated on `topology == 'ha'`, the
same expression `addon-database`'s CloudNativePG install already uses),
depending on `csi` for storage, plus a `resources` tier carrying the
`ClusterSecretStore` bound to the in-cluster instance. Auth is local: the
cluster's own OpenBao trusts its own API server via OpenBao's Kubernetes
auth method — no cross-cluster registration, no static credential.

**Unseal is a bootstrap-ordering problem, solved the way the existing
`kubernetes` secrets path already solves one.** OpenBao needs its unseal
material before it will serve anything — before ESO can sync a single
Secret out of it. A Terraform step generates the unseal (or recovery)
key once, holds it in state, and a facet `secrets:` block places it as a
plain `Secret` via [ADR-0002](0002-cluster-secrets-management.md)'s
already-shipped path — never as an `ExternalSecret`, which would be
circular. This mirrors the existing `pki.private_ca` keypair's own
Terraform-generated-then-placed pattern.

### 3. `driver: external` — point at a store this cluster doesn't own

No `install` tier at all. Only a `resources` tier emitting the
`ClusterSecretStore`, pointed at the operator-supplied `url`, using
Kubernetes auth against the given `mount_path`/`role`. This is the shape
a downstream fleet cluster uses to read from Windsor Manager's shared
OpenBao, and equally the shape for an operator who already runs their
own HashiCorp Vault and wants core to talk to it rather than install
anything.

### 4. Requires External Secrets Operator

`secrets_store.enabled` on its own is meaningless without
[ADR-0004](0004-external-secrets-operator.md)'s controller running to
read from the `ClusterSecretStore` it creates — a `requires:` gate
enforces `external_secrets.enabled == true` in the facet, phrased for
the operator ("the secrets store needs External Secrets turned on too"),
not in terms of `ClusterSecretStore`/CRD internals.

## Consequences

- One provider family, two topologies. Consumers (ADR-0002's
  `ExternalSecret` materialization) see the same `ClusterSecretStore`
  shape regardless of which driver produced it.
- **`openbao` is the only self-hosted option.** HashiCorp Vault is fully
  usable via `driver: external` (an operator's own Vault instance), just
  never installed by this addon.
- **`external` is the seam Windsor Manager's fleet model depends on.**
  Without it, a downstream cluster would have to run its own store
  rather than reading from the fleet's shared one — this driver is what
  makes core usable as a downstream-cluster blueprint under Manager, not
  only as a standalone one.
- Self-hosted OpenBao's unseal material is secured by the same mechanism
  as any other Terraform-generated, facet-placed secret (a Terraform
  state file) — an appropriate v0.8.0 answer, not a permanent one for
  anyone auditing the cluster's root-of-trust story.

## Alternatives considered

**A `driver: vault` self-hosted option alongside `openbao`.** Redundant
chart to build and maintain for a product under a license this repo
doesn't otherwise depend on, when OpenBao is the drop-in open
replacement and `external` already covers anyone who wants to run their
own Vault.

**Self-hosted only, no `external` driver.** Matches core#2285's original
scope exactly, but breaks Windsor Manager's fleet model, which
explicitly needs a downstream cluster reading from a store it doesn't
own. Adding `external` costs one enum value and a handful of connection
fields.

**Cloud KMS auto-unseal for the self-hosted case.** Removes the
Terraform-state-held-key question entirely on AWS/Azure. Rejected as the
*only* path because it doesn't exist on Hetzner, vSphere, Hyper-V, Incus,
or metal — core runs on all of those. Worth offering as a per-platform
override later, not the default.

## References

- [core#2284](https://github.com/windsorcli/core/issues/2284),
  [core#2285](https://github.com/windsorcli/core/issues/2285) — the
  issues this ADR and ADR-0004 formalize.
- [ADR-0002](0002-cluster-secrets-management.md),
  [ADR-0004](0004-external-secrets-operator.md) — the materialization
  and controller this store serves.
- `contexts/_template/facets/addon-database.yaml` — the `topology == 'ha'`
  gating and `dependsOn: [csi]` pattern this addon's `openbao` driver
  follows.
- `contexts/_template/facets/addon-private-ca.yaml` — the
  Terraform-generate-once, facet-place-as-plain-Secret pattern the
  unseal material reuses.
- OpenBao: [openbao.org](https://openbao.org). ESO's `vault` provider:
  [external-secrets.io](https://external-secrets.io/latest/provider/hashicorp-vault/).
