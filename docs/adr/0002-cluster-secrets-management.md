---
title: "ADR-0002: Cluster secrets — ExternalSecret materialization over the shipped sensitive/secrets: mechanism"
description: "The sensitive: schema marker and the flux: system secrets:/data: mechanism are shipped (plain Secret only, cli #3022/#3091/#3100). This ADR decides how the same facet-authored secrets: entries materialize as an ExternalSecret instead, once ADR-0004 (External Secrets Operator) and ADR-0005 (secrets store) are both enabled — no new driver field, no schema key collision with the existing build-time secrets: block."
---

# ADR-0002: Cluster secrets — ExternalSecret materialization over the shipped sensitive/secrets: mechanism

## Status

Proposed (2026-07-20). Revised (2026-08-04): the plain-`Secret` path is
shipped and in production use — the `sensitive:` schema marker and a
`flux:`-system `secrets:` block already materialize a Kubernetes `Secret`
end to end (cli #3022, #3091; live in five core facets, see Shipped below).
This ADR is rescoped to the one thing left: materializing the same
`secrets:` entries as an `ExternalSecret` instead, once
[ADR-0004](0004-external-secrets-operator.md) (the controller) and
[ADR-0005](0005-secrets-store.md) (a store) are both enabled. `sops` is
dropped from this ADR's scope — no consumer needs it today; see Open
questions.

## Context

### The problem

A facet often needs a Secret inside a Flux-owned namespace — the
motivating case was the Alertmanager Slack webhook token in
`system-telemetry`. Terraform can only write Secrets into namespaces it
owns (`flux-system`), and each add-on namespace is created later by its
own Flux Kustomization, so there was no committed-to-git path to get a
value there. The shipped mechanism below closes that gap; a prior
Cloudflare-token workaround that cloned a Secret cross-namespace with
Kyverno is no longer needed for any new consumer.

### Shipped: sensitive properties materialize as a plain Secret

A schema property can be marked **`sensitive: true`** (5 properties in
`contexts/_template/schema.yaml` today: `hetzner.token`,
`telemetry.alerts.slack.webhook_url`, `pki.private_ca.cert`/`.key`,
`gitops.webhook.token`). A facet wires one into a `flux:` system with a
`secrets:` block — key names the generated `Secret`, `data:` maps its
keys to sensitive property references, and an optional `namespaces:`
list targets more than one namespace (used by `addon-private-ca.yaml`
and `platform-hetzner.yaml`'s `pki` entry to land the same secret in
`system-pki` alongside its owning system):

```yaml
# facet
flux:
  - name: telemetry
    secrets:
      alertmanager-notification-slack:
        data:
          url: ${telemetry.alerts.slack.webhook_url}
```

At composition `cli` resolves the referenced value and writes a plain
Opaque `Secret` into the target namespace(s), ordered after the owning
system's `install` Kustomization. Five facets use this today
(`addon-identity.yaml`, `addon-observability.yaml`,
`addon-private-ca.yaml`, `platform-hetzner.yaml`, `platform-base.yaml`).
This ADR is about giving that same `secrets:` entry a second
materialization, not about changing how a facet author writes one.

### How secret references actually work in `cli` (verified from source)

This matters because earlier drafts of this ADR invented mechanisms
that don't match it:

- **A secret reference is an expression, written inline where a value
  is needed** — `secret("vault", "item", "field")`, or dotted sugar
  `secrets.op.<vault>.<item>.<field>` / `secrets.sops.<key.path>`
  (`NormalizeExpression`). There is no "named secret catalog" concept.
- **`secret.`/`secrets.` are reserved expression prefixes.** The
  evaluator (`evaluator.go:305`) normalizes first; `secrets.op.*` /
  `secrets.sops.*` resolve as secrets, anything else falls through to a
  normal config-path lookup. Only `op` and `sops` are recognized
  providers in the dotted form.
- **Two-pass evaluation.** During composition `secret()` returns a
  `DeferredError` and stays raw; after terraform apply,
  `handler.go:resolveDeferredSubstitutions` re-evaluates with
  `evaluateDeferred=true` and resolves it into the substitution/ConfigMap.
- **`cli` can parse without resolving** — `parseSecretNotationParts` /
  `parseHelperParams` extract `(vault, item, field)` from a `secret()`
  expression. Needed for the ExternalSecret path, which must keep the
  coordinates, not fetch the value.
- **The existing `secrets:` block means one specific thing already** —
  providers backing build-time `secret()` references (`onepassword.vaults`
  today). Manager's own schema explicitly flags the collision risk of
  reusing this key for anything else: *"Core's `secrets` block is the set
  of providers backing build-time `secret()` references, not an in-cluster
  secrets backend; a management-side store needs its own key rather than
  an extra property there."* This ADR takes that warning at face value —
  no `driver` field goes under `secrets:`. See Decision.

### Namespaces and Flux ordering

A `flux:` **system** compiles to an `install` Kustomization (which owns
the namespace via `install/namespace.yaml`) plus `resources`
Kustomizations that implicitly `dependsOn` it. So a secret tied to a
system lands in that system's namespace, correctly ordered, for free.

## Decision

### 1. No new field on the existing `secrets:` block

The materialization a `flux:`-system `secrets:` entry gets is *implicit*,
not a schema toggle: plain `Secret` when
[ADR-0005](0005-secrets-store.md)'s `secrets_store.enabled` is `false`
(today's shipped behavior, unchanged), `ExternalSecret` when both
[ADR-0004](0004-external-secrets-operator.md)'s `external_secrets.enabled`
and `secrets_store.enabled` are `true`. There is no `secrets.driver`
enum, and nothing is added to the build-time `secrets:` block — avoiding
exactly the key collision Manager's own schema comment calls out.

### 2. Composition materializes each entry by whether a store is present

At composition, for each `flux:`-system `secrets:` entry, windsor
resolves the referenced sensitive property to its raw config
expression:

- **Store absent** — resolve the value (deferred pass), emit a plain
  `Secret`. Unchanged from today.
- **Store present** — **parse** the property's `secret()` reference for
  `(vault, item, field)` *without resolving*, emit an `ExternalSecret`
  (or one per namespace, for a `secrets:` entry using `namespaces:` —
  see Open questions): `secretStoreRef` = the `ClusterSecretStore`
  [ADR-0005](0005-secrets-store.md) creates, `remoteRef.key`/`.property`
  = `item`/`field`.

This is a new pass in `pkg/composer/blueprint/`. It runs *instead of*
normal deferred resolution for `secrets:` entries once a store is
present (it must parse, not resolve); with no store it is exactly the
resolve path that already ships.

## Implementation surface

**`cli` changes:**

1. Composer (`pkg/composer/blueprint/`): the new pass that, per
   `flux:`-system `secrets:` entry, checks whether a `ClusterSecretStore`
   is present and, if so, parses `(vault, item, field)` and emits an
   `ExternalSecret` instead of resolving and emitting a `Secret`. Scoped
   to the `secrets:` key; existing `secret()` behavior in
   substitutions/`.env`/terraform is untouched.
2. Nothing changes in schema — no `driver` field, no new block.

**core changes:**

1. Facets: `dependsOn` on [ADR-0005](0005-secrets-store.md)'s system
   under the `secrets_store` capability, so an `ExternalSecret` never
   composes before its `ClusterSecretStore` exists.

## Consequences

- **Namespace ordering is free** — the secret is tied to a `flux:`
  system, so it lands in that system's namespace, already ordered by
  the system's own `resources`→`install` edge. No namespace
  abstraction.
- **One cluster-wide switch, not per-secret choices** — every sensitive
  secret in the cluster moves to `ExternalSecret` together, driven by
  whether [ADR-0005](0005-secrets-store.md)'s store is enabled. A facet
  author never picks a materialization.
- **No schema surface added by this ADR** — the decision lives entirely
  in composer behavior conditioned on two other addons' enablement.
- **Fail closed** — a sensitive property whose value isn't a resolvable
  `secret()` reference when a store is present.

## Open questions

- **Paired namespaces.** The shipped plain-`Secret` path's `namespaces:`
  list already handles a secret needed in more than one namespace (used
  by `pki`/`pki-trust` today). The `ExternalSecret` path should follow
  the same pattern — one `ExternalSecret` per paired namespace — rather
  than inventing a second mechanism.
- **`sops` — deferred, not decided against.** A SOPS-encrypted `Secret` +
  Flux `spec.decryption` is a real third posture (nothing plaintext in
  git, no operator in the cluster) but has no consumer asking for it
  today, unlike `ExternalSecret`, which [ADR-0005](0005-secrets-store.md)
  exists specifically to serve. Revisit if a context needs a
  git-committed-and-encrypted secret with no runtime store at all.
- **Value transits the apply host.** The plain-`Secret` path resolves the
  `secret()` at `windsor apply` time via the operator's provider config,
  so the plaintext passes through the apply host — acceptable, same as
  any `secret()` today, but the reason the `ExternalSecret` path (value
  never leaves the store) is the stronger posture for anything sensitive
  enough to matter.

## Alternatives considered

- **A `secrets.driver` enum on the existing `secrets:` block** (the
  original draft of this ADR) — collides with that block's settled
  meaning (build-time `secret()` provider config), a collision Manager's
  own schema comments explicitly warn against. Replaced by making the
  materialization implicit on the other two addons' enablement.
- **A `secrets.refs`/named-catalog of secret references** (earlier
  drafts) — invents a construct windsor doesn't have; a reference is an
  expression at a config path. Replaced by marking the property
  `sensitive` at its natural location.
- **Facet-authored `secret()` literals or raw `ExternalSecret` YAML** —
  hardcodes an operator's vault/item/field into shared content, or
  couples the facet to ESO's CRD with no clean provenance. The facet
  only ever names a sensitive property path.
- **Terraform or the CLI writing Secrets directly into add-on
  namespaces** — an external imperative write outside GitOps; the repo's
  principle is that in-cluster objects are managed by Flux or an
  operator Flux installs.
- **Kyverno clone for multi-namespace** (the earlier Cloudflare
  workaround) — `ExternalSecret` per namespace is the native answer and
  needs no policy engine.

## References

- `cli` `pkg/runtime/secrets/secrets.go` (`SecretRef`, `NormalizeExpression`,
  `parseSecretNotationParts`), `evaluator.go:305`,
  `api/v1alpha2/config/secrets/schema.yaml` — the verified
  secret-reference mechanics.
- `cli` `pkg/composer/blueprint/` (`composer.go`,
  `handler.go:resolveDeferredSubstitutions`),
  `pkg/runtime/config/schemas/artifacts/facets.yaml` (`config:` blocks,
  `requires:`, `flux:`) — where interpretation happens and how facets
  declare inputs.
- [ADR-0004](0004-external-secrets-operator.md),
  [ADR-0005](0005-secrets-store.md) — the two addons this ADR's
  materialization depends on.
- Flux: [Secrets Management](https://fluxcd.io/flux/security/secrets-management/).
  ESO: [GitOps using FluxCD](https://external-secrets.io/latest/examples/gitops-using-fluxcd/).
- `contexts/_template/facets/addon-observability.yaml`'s
  `alertmanager-notification-slack` entry — the shipped plain-`Secret`
  path's first consumer.
