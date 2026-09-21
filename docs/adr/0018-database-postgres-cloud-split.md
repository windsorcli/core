---
title: "ADR-0018: Split database.postgres.driver into a baseline CNPG flag and an opt-in cloud object"
description: "database.postgres.driver is one enum today — cloudnativepg | rds | azuredb | cloudsql — so choosing a cloud driver for an app chart's database silently turns off CNPG, the operator core's own Keycloak depends on unconditionally. Splits postgres.enabled (CNPG, unconditional default) from a new postgres.cloud.enabled/cloud.driver (opt-in, additive). Revises ADR-0009 §1."
---

# ADR-0018: Split database.postgres.driver into a baseline CNPG flag and an opt-in cloud object

## Status

Proposed. Revises [ADR-0009](0009-crossplane-cloud-databases.md) §1's original
"reuse `database.postgres`, `driver` selects the implementation" call, formalizing
[core#2864](https://github.com/windsorcli/core/issues/2864). Not yet
implemented or verified live.

## Context

`database.postgres.driver` is one enum —
`cloudnativepg | rds | azuredb | cloudsql` — never more than one value active
per context. That one field is asked to answer two questions that don't
compete with each other:

- **Does core's own baseline utility Postgres run?** CloudNativePG backs
  in-cluster services core itself depends on. Today that's Keycloak:
  `addon-identity.yaml`'s `database` resource requests a
  `postgresql.cnpg.io/v1 Cluster` unconditionally and blocks on its `Ready`
  condition (`addon-identity.yaml:82-94`), with no `driver` check anywhere
  in that block.
- **Does a customer's Helm chart also want a cloud-managed Postgres as an
  application dependency?** `rds`/`azuredb`/`cloudsql` exist for exactly
  that (ADR-0009), installed after `windsor apply`, unrelated to whether
  core's own services need CNPG.

Because both questions read the same field, answering the second one turns
off the first for everyone, Keycloak included.

### The concrete bug this produces today

`addon-database.yaml`'s `database` Flux entry only installs the CNPG
operator when the driver is `cloudnativepg`:

```yaml
components:
  - "${database.postgres.driver == 'cloudnativepg' ? 'cloudnativepg' : ''}"
```

`addon-identity.yaml`'s Keycloak `database` resource has no such gate. It
always requests a `Cluster` CR and depends on `database-install`
(`addon-identity.yaml:83-94`):

```yaml
- name: database
  dependsOn: [database-install]
  components: [keycloak/database, ...]
  healthCheckExprs:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      current: status.conditions.exists(e, e.type == 'Ready' && e.status == 'True')
```

`identity` is enabled by default. Set `database.postgres.driver: rds` for
an app chart's own database — the ordinary way to opt into ADR-0009's
capability — and `database-install`'s `components:` list evaluates to
nothing, so no CNPG operator runs, while Keycloak's `Cluster` CR still gets
created and still gets waited on. `identity-resources-database` never
completes; `identity` hangs; Keycloak never comes up. No `requires:` guard
in either facet catches this combination before `windsor apply`.

`addon-identity.yaml` already works around the sharing at the config layer,
not the root cause — its own `database` config block passes the value
through rather than setting it:

```yaml
- name: database
  value:
    postgres:
      enabled: "${(identity.driver ?? 'keycloak') == 'keycloak' ? (database.postgres.enabled != false) : (database.postgres.enabled ?? false)}"
      driver: "${database.postgres.driver ?? 'cloudnativepg'}"
```

`enabled` is forced on for the `keycloak` driver; `driver` is a plain
passthrough (`?? 'cloudnativepg'` only fires when nothing set it), so an
explicit `driver: rds` from the app-database side survives untouched and
still breaks Keycloak.

### Every other consumer of `driver` treats it the same conflated way

Checked directly against every current reference in
`contexts/_template/facets/`, not assumed:

- **`addon-database.yaml`** (`lines 18-222`) — three `terraform:` pairs
  gated on `driver == 'rds' | 'azuredb' | 'cloudsql'`; the `database` Flux
  entry's operator-install list and `csi-install`/`telemetry` `dependsOn`
  gated on `driver == 'cloudnativepg'`; the `observability` Flux entry
  picks one of two dashboards on the same four-way check; the
  `provisioning` Flux entry (Crossplane engine + driver-specific
  components) gated on the three cloud values.
- **`option-single-node.yaml:49`** — the `database` system's single-node
  patch guards on `database.postgres.enabled == true && database.postgres.driver == 'cloudnativepg'`.
- **`option-dev.yaml:31`** — same passthrough pattern as `addon-identity.yaml`:
  `driver: "${database.postgres.driver ?? 'cloudnativepg'}"`.
- **`option-demo.yaml`** — `database_instance_name` picks a naming
  convention on `driver == 'azuredb'`; four `demo` Flux entries, one per
  driver value, each gated on an exact match.
- **`platform-base.yaml:230-231`** — `alert_components` picks
  `prometheus/alerts/database` (CNPG) vs. `prometheus/alerts/postgres-exporter`
  (cloud) off the same four-way check. (The `postgres-exporter` line
  already only tests `rds`/`azuredb`, missing `cloudsql` — a pre-existing
  gap, unrelated to this ADR, left alone here.)
- **`schema.yaml`** — the driver/platform coherence checks fixed in
  [core#2884](https://github.com/windsorcli/core/issues/2884) (four `if`/`then`
  blocks keying off `platform`, restricting which `driver` values are
  valid).

Not one of these needed `driver == 'cloudnativepg'` to mean anything other
than "the baseline operator is active," and not one needed the three cloud
values to mean anything other than "an app-facing cloud database is
requested." The conflation is uniform, which is what makes splitting it a
mechanical rename at every site rather than a redesign of any one of them.

## Decision

### 1. `postgres.enabled` is the baseline; `postgres.cloud` is the additive opt-in

```yaml
database:
  postgres:
    enabled: true        # CloudNativePG. Independent of everything below.
    cloud:
      enabled: false      # opt-in: also expose a cloud-managed Postgres for app charts.
      driver: rds          # rds | azuredb | cloudsql. Required when cloud.enabled.
      encryption:
        managed: false
        key_id: ""
```

`cloudnativepg` MUST NOT remain a `driver` value. It drops out of the enum
entirely and becomes what `postgres.enabled` already means on its own —
the same relationship `gateway.enabled`/`gateway.driver` and
`identity.enabled`/`identity.driver` already have, where `enabled` gates a
capability wholesale and `driver` only ever selects among the ways to
fulfill it once the capability is already on. `cloud.driver` mirrors that
relationship one level down: `cloud.enabled` gates the cloud database as its own
capability, `cloud.driver` picks which cloud fulfills it.

`postgres.encryption.*` moves to `postgres.cloud.encryption.*`. Its
description was always cloud-specific — "a dedicated customer-managed key
instead of the driver's platform-managed default" — CNPG has no cloud KMS
concept to opt into; the field only ever meant something for
`rds`/`azuredb`/`cloudsql`. Nesting it under `cloud` says that directly
instead of leaving it a sibling of `driver` that happened to be a no-op
for one of that field's four values.

`cloud.driver` has no default, matching `gateway.driver`'s own
precedent (no default; a platform facet or a `requires:` check pins the
valid value). `requires:` (§4) makes it mandatory the moment
`cloud.enabled: true` is set, so composition fails at the field that's
actually missing rather than silently picking a driver the platform can't
serve.

### 2. Every `driver == 'cloudnativepg'` gate becomes `enabled == true`

`addon-database.yaml`'s `database` Flux entry:

```yaml
install:
  components:
    - "${database.postgres.enabled == true ? 'cloudnativepg' : ''}"
    - "${database.postgres.enabled == true ? 'cloudnativepg/prometheus' : ''}"
    - "${database.postgres.enabled == true && topology == 'ha' ? 'cloudnativepg/ha' : ''}"
```

This entry's own `when: database.postgres.enabled == true` (facet-level,
already the case today) makes the `install.components` check redundant
with the `when:` itself once cloudnativepg is the only thing `enabled`
gates — worth dropping the per-line ternary for a plain unconditional
list at implementation time, not carried as a design decision here since
it's a simplification, not a behavior change.

`option-single-node.yaml:49` and `platform-base.yaml:230` follow the same
substitution: `database.postgres.driver == 'cloudnativepg'` →
(redundant with the surrounding `enabled` check, see above) or dropped
outright where `enabled` is already being tested on the same line.

### 3. Every `driver == '<cloud>'` gate becomes `cloud.enabled == true && cloud.driver == '<cloud>'`

`addon-database.yaml`'s `terraform:` and Flux `provisioning`/`observability`
entries, `option-demo.yaml`'s four driver-keyed entries, and
`platform-base.yaml:231`'s `postgres-exporter` alert line all follow this
substitution mechanically. Example, `addon-database.yaml`'s `rds` KMS/SG
terraform step:

```yaml
- name: database
  path: database/aws-rds
  when: "database.postgres.cloud.enabled == true && database.postgres.cloud.driver == 'rds'"
  ...
  inputs:
    manage_encryption_key: ${(database.postgres.cloud.encryption.managed ?? false) && !(ephemeral ?? false)}
    key_id: "${database.postgres.cloud.encryption.key_id ?? ''}"
```

The `observability` Flux entry's dashboard picker collapses from a
four-way check to two independent conditions, since CNPG and cloud are no
longer mutually exclusive:

```yaml
- name: observability
  when: (database.postgres.enabled == true || database.postgres.cloud.enabled == true) && observability.enabled == true
  resources:
    - components:
        - "${database.postgres.enabled == true ? 'grafana/dashboards/cloudnativepg' : ''}"
        - "${database.postgres.cloud.enabled == true ? 'grafana/dashboards/postgres-exporter' : ''}"
```

This changes real behavior, not only naming: a context with both
`postgres.enabled: true` (Keycloak's CNPG instance) and
`postgres.cloud.enabled: true` (an app's RDS instance) now correctly gets
both dashboards, where today it can only ever get one — the exact
capability this ADR is restoring.

### 4. `requires:` closes the gap no check caught before

`schema.yaml` gains a `required: [driver]` conditional keyed on
`cloud.enabled`, next to the platform/driver coherence checks
[core#2884](https://github.com/windsorcli/core/issues/2884) already fixed to key
off `platform`:

```yaml
- if:
    properties:
      database:
        properties:
          postgres:
            properties:
              cloud:
                properties:
                  enabled:
                    const: true
                required: [enabled]
            required: [cloud]
        required: [postgres]
    required: [database]
  then:
    properties:
      database:
        properties:
          postgres:
            properties:
              cloud:
                required: [driver]
```

The four platform/driver coherence blocks from #2884 move to key off
`cloud.driver` instead of `driver`, and the fourth block (any platform
outside `aws`/`azure`/`gcp`) changes from "`driver` must be
`cloudnativepg`" to "`cloud.enabled` must be `false`" — there's no longer
a value for `cloud.driver` to fall back to on those platforms, since
`cloudnativepg` isn't a `cloud.driver` option at all:

```yaml
# Any other platform cannot serve a cloud-managed Postgres.
- if:
    properties:
      platform:
        not:
          enum: [aws, azure, gcp]
    required: [platform]
  then:
    properties:
      database:
        properties:
          postgres:
            properties:
              cloud:
                properties:
                  enabled:
                    const: false
```

`addon-identity.yaml`'s `database` config block's `driver` passthrough
line (`driver: "${database.postgres.driver ?? 'cloudnativepg'}"`) is
deleted outright, not translated — once `enabled` and `cloud` are
independent, Keycloak's CNPG dependency needs nothing from this facet
beyond forcing `postgres.enabled: true`, which the existing `enabled:`
line already does. `option-dev.yaml:31`'s identical passthrough is
deleted the same way, for the same reason. This alone closes the bug in
Context: nothing an app-database operator sets under `cloud.*` can reach
`postgres.enabled` anymore, by construction, not by a guard catching it
after the fact.

A `requires:` guard rejecting `identity.driver: keycloak` combined with
an *explicit* `database.postgres.enabled: false` was considered here and
dropped after checking the mechanism directly, not assumed. Verified
with a scratch `windsor test` case: `requires:`'s `paths:` check tests
whether the operator's raw input supplied a path at all, not the
resolved value — `identity.enabled: false`, set explicitly, composes
clean against a `paths: [identity.enabled]` requirement
(`addon-observability.yaml:31-33`'s existing SSO guard), where omitting
`identity:` entirely correctly fails the same check. `paths:` cannot
distinguish "explicitly false" from "true," which rules it out for this
case on its own — and moot besides, since this facet's own `config:`
block (`enabled: "${... ? (database.postgres.enabled != false) : ...}"`)
always writes some value to `database.postgres.enabled` before any
`requires:` check downstream could run, so the path is never actually
absent by the time one would look. An operator explicitly disabling the
database their own hosted Keycloak depends on is a real footgun, but a
pre-existing one, unrelated to the `driver`/`cloud` conflation this ADR
fixes and not newly introduced by it — left as a separate, narrower gap
rather than papered over with a `requires:` block that only looks like
protection.

## Consequences

- **This is a breaking schema change**, acceptable under
  [ADR-0003](0003-versioning-and-upgrade-contract.md)'s pre-1.0 0ver
  contract (a breaking change bumps minor, not major). An existing
  context with `database.postgres.driver: cloudnativepg` set explicitly —
  the common case, since it's also the default — fails composition
  outright once `driver` moves under `cloud` and top-level `postgres`
  keeps `additionalProperties: false`: `cloudnativepg` is no longer a
  valid `cloud.driver` value, and `driver` is no longer a valid sibling of
  `enabled`. The fix is deleting that line; the field said nothing
  `enabled: true` doesn't already say. No migration shim is proposed —
  the operator action is a one-line values.yaml edit, called out plainly
  in the release notes rather than absorbed into a compatibility branch
  in `schema.yaml` for a value that was already redundant with the
  default.
- An existing context with `database.postgres.driver: rds` (or
  `azuredb`/`cloudsql`) set needs its own one-line rewrite:
  `postgres.cloud.enabled: true` plus `postgres.cloud.driver: rds`.
  Unlike the `cloudnativepg` case, this also changes behavior on upgrade
  in the operator's favor: today's config silently disables CNPG as a
  side effect; the rewritten config does not, closing exactly the bug
  this ADR exists to fix. An operator relying on that side effect (CNPG
  actually off, whether or not they meant it) sees it turn back on. Worth
  flagging, not blocking: nothing in the codebase or ADR-0009 documents
  turning CNPG off as an intended lever of setting a cloud driver, so
  there's no known deliberate use of the old side effect to preserve.
- Every schema/facet site enumerated in Context gets touched:
  `schema.yaml` (driver enum relocation, encryption relocation, four
  coherence checks, new `requires:`), `addon-database.yaml`,
  `addon-identity.yaml`, `option-single-node.yaml`, `option-dev.yaml`,
  `option-demo.yaml`, `platform-base.yaml`. All twelve `.test.yaml` cases
  in `addon-database.test.yaml` that set `driver:` explicitly (rds/azuredb/
  cloudsql cases) need their `values:` blocks rewritten to the new
  `cloud.enabled`/`cloud.driver` structure; new cases are needed for the
  combination this ADR restores (`postgres.enabled: true` and
  `postgres.cloud.enabled: true` together, asserting both Grafana
  dashboards render) and for the new schema-level `requires:`
  (`cloud.enabled: true` with no `cloud.driver` failing composition).
- Catalog docs benefit from the same split the issue originally named:
  CloudNativePG stops reading as "one sibling among four" and the cloud
  drivers become clearly-labeled variants of one additive capability,
  independent of whether core's own baseline Postgres is on. Not
  implemented as part of this ADR; a doc follow-up once the schema lands.
- `terraform_output('database', ...)` references in `addon-database.yaml`
  and `option-demo.yaml` are unaffected — the Terraform layer names
  (`database/aws-rds`, `database/azure-postgres`, `database/gcp-cloudsql`)
  and their output contracts don't change, only the schema path that
  gates them.

## Alternatives considered

**Leave `driver` as one enum, add a `requires:` guard instead.** Closes
the specific Keycloak-hang bug with far less churn — one `requires:` block
in `addon-identity.yaml` rejecting `identity.driver: keycloak` combined
with any non-`cloudnativepg` `database.postgres.driver`. Rejected: it
papers over the real defect, that two independent capabilities share one
field, without fixing it. It also forecloses the case this ADR's §3
restores on purpose — a context running Keycloak on CNPG *and* an app
chart on RDS simultaneously — which core#2864 identifies as a legitimate
combination the schema should support, not an error to reject.

**A new top-level `crossplane` capability**, mirroring the alternative
ADR-0009 itself already considered and rejected for the same reason: the
concrete need is still a database, and `database.postgres` already has
the right nested-object precedent (`gateway`, `identity`) to extend rather
than replace.

**Keep `cloudnativepg` in the `cloud.driver` enum as a fourth, no-op
value**, avoiding the `additionalProperties: false` break for existing
contexts. Rejected: it keeps the exact ambiguity this ADR exists to
remove — a `cloud.driver: cloudnativepg` value would mean "the cloud
capability is on, fulfilled by using no cloud at all," which the
`cloud.enabled` boolean already expresses unambiguously without an enum
value that names nothing.

## References

- [core#2864](https://github.com/windsorcli/core/issues/2864) — the issue
  this ADR formalizes, including the proposed schema structure §1 refines.
- [ADR-0009](0009-crossplane-cloud-databases.md) §1 — the original
  single-enum decision this ADR revises.
- [core#2884](https://github.com/windsorcli/core/issues/2884) — the
  platform/driver coherence-check fix §4's `requires:` blocks build on.
- [ADR-0003](0003-versioning-and-upgrade-contract.md) — the pre-1.0 0ver
  contract this ADR's breaking change relies on.
- `contexts/_template/facets/addon-database.yaml`,
  `addon-identity.yaml`, `option-single-node.yaml`, `option-dev.yaml`,
  `option-demo.yaml`, `platform-base.yaml` — every current consumer of
  `database.postgres.driver`, enumerated in Context.
- `contexts/_template/schema.yaml` (`gateway.enabled`/`gateway.driver`,
  `identity.enabled`/`identity.driver`) — the `enabled`-gates-capability,
  `driver`-selects-implementation precedent this ADR's `cloud.enabled`/
  `cloud.driver` follows one level deeper.
