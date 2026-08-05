---
title: "ADR-0004: External Secrets Operator — runtime secret sync addon"
description: Adds a top-level external_secrets capability that installs External Secrets Operator, install-only, off by default. Closes core#2284. The controller alone does nothing without a ClusterSecretStore; ADR-0005 supplies one.
---

# ADR-0004: External Secrets Operator — runtime secret sync addon

## Status

Proposed. Formalizes [core#2284](https://github.com/windsorcli/core/issues/2284).
Depended on by [ADR-0002](0002-cluster-secrets-management.md) (the `externalsecret`
materialization) and [ADR-0005](0005-secrets-store.md) (the store this controller
reads from).

## Context

`secret()` resolves build-time references — through the providers under the
top-level `secrets:` block — into generated values. Nothing syncs a *live*
credential into a running cluster; anything needing one has it baked in at
compose time. External Secrets Operator (ESO) is the client half of that gap
and belongs in core unconditionally: every cluster runs it, standalone or
not, regardless of what store sits behind it.

## Decision

### 1. A top-level `external_secrets` capability

```yaml
external_secrets:
  enabled: false
```

Top-level, not nested under `addons:` — the `addons` namespace was flattened
into top-level capability keys ([core#2348](https://github.com/windsorcli/core/issues/2348));
`identity`, `database`, `object_store` are the precedent.

### 2. Install-only, no store

A `flux:` system installing the operator only — it manages `ExternalSecret`
and `ClusterSecretStore` CRs and creates none of its own, the same shape as
`addon-database`'s CloudNativePG install. CRDs vendor under
`kustomize/crds/external-secrets-<version>/`, matching how cert-manager and
the AWS LB controller's CRDs are already vendored.

No `ClusterSecretStore` is created here. A store is per-backend and belongs
to whatever add-on backs it — [ADR-0005](0005-secrets-store.md) for the
in-repo case.

## Consequences

- Enabling `external_secrets` alone does nothing observable — no
  `ClusterSecretStore` exists yet, so no `ExternalSecret` can resolve. This
  is deliberate: the controller and the store are independently enable-able
  because a cluster can run ESO pointed at a store it doesn't host itself.
- [ADR-0002](0002-cluster-secrets-management.md)'s `externalsecret`
  materialization requires both this addon and a store enabled; neither
  addon depends on the other.

## Alternatives considered

**Bundle the controller and a self-hosted store behind one flag.** Simpler
surface, but forecloses a cluster pointing ESO at a store it doesn't own —
exactly the shape a downstream fleet cluster needs when a management
cluster hosts the shared store. Keeping them separate costs one extra
toggle and buys that case.

## References

- [core#2284](https://github.com/windsorcli/core/issues/2284) — the issue
  this ADR formalizes.
- `contexts/_template/facets/addon-database.yaml` — the install-only,
  creates-nothing pattern this addon follows.
- `kustomize/crds/` — the existing vendored-CRD convention.
