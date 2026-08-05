---
title: "ADR-0006: SeaweedFS as a second object_store driver"
description: Adds object_store.driver enum value seaweedfs alongside the shipped minio. No CRD/operator tier like MinIO's Operator+Tenant split — SeaweedFS is Helm-chart-native StatefulSets. HA requires the filer's metadata store to move off embedded LevelDB onto the existing database capability, a dependency MinIO's HA story doesn't have.
---

# ADR-0006: SeaweedFS as a second `object_store` driver

## Status

Proposed.

## Context

`object_store` today has one driver, `minio` (`contexts/_template/schema.yaml`
~1336): an Operator-only install (`kustomize/object-store/install/minio/`)
that provisions no Tenant by default — consumers reference the reference
Tenant under `resources/common/` or bring their own. Storage class is not
derived from `topology`; there is no `object_store_effective` or
cross-facet config block, and no other facet reads `object_store.*` today
besides the facet's own test.

SeaweedFS is a real second option for platforms where MinIO's
per-object-on-PVC model and Operator+Tenant split cost more than the
alternative buys: no community-standard operator/CRD tier at all —
master, volume, filer, and S3-gateway are plain Helm-chart StatefulSets,
which is a simpler two-tier story than MinIO's Operator-then-Tenant
split, not a more complex one.

## Decision

### 1. `driver: seaweedfs` alongside `minio`

```yaml
object_store:
  driver:
    enum: [minio, seaweedfs]
  seaweedfs:
    filer_store:
      enum: [leveldb, postgres]
      default: leveldb
    replication:
      default: "000"
```

`filer_store` and `replication` are SeaweedFS-specific and nest under
`object_store.seaweedfs`, the same way `database.postgres.driver` nests
Postgres-specific fields one level under `database.postgres` rather than
flattening them onto `object_store` itself.

### 2. Components: master, volume, filer, S3 gateway

```yaml
flux:
  - name: object-store
    when: object_store.driver == 'seaweedfs'
    dependsOn:
      - csi
      - "${object_store.seaweedfs.filer_store == 'postgres' ? 'database' : ''}"
    install:
      components:
        - seaweedfs/master
        - seaweedfs/volume
        - seaweedfs/filer
        - seaweedfs/s3
        - "${topology == 'ha' ? 'seaweedfs/ha' : ''}"
```

- **master** — Raft-based metadata/topology coordinator; a 3-replica
  quorum under `ha`, the same shape as CNPG's HA `Cluster` or Longhorn's
  `ha/` patch.
- **volume** — the data-bearing StatefulSet, PVC-backed via `csi`; this
  is where `replication` (SeaweedFS's placement code — extra copies per
  rack/data-center/node) applies.
- **filer** — owns bucket/path metadata, backed by `filer_store`.
- **s3** — the S3-API-compatible gateway consumers talk to, the
  SeaweedFS analogue of MinIO's Tenant `Service`.

### 3. `topology: ha` requires `filer_store: postgres`

Embedded LevelDB is local-disk and single-writer — it does not support
more than one filer replica, so it cannot be made HA. Postgres is
stateless and horizontally scalable, and it's already a capability this
repo has (`database`). A `requires:` gate enforces this in operator
vocabulary — *"object storage HA needs the database service enabled"* —
rather than silently switching `filer_store` underneath the operator or
failing deep inside a Helm values render.

This is the one place SeaweedFS's HA story pulls in a dependency MinIO's
doesn't have: MinIO Tenant HA (more pools/servers) is self-contained.

### 4. `minio` stays the default

SeaweedFS's argument is resource footprint and small-object efficiency
at the storage layer, which matters most on platforms without cloud CSI
economics (metal, Hyper-V) — a footprint argument, not a reason to make
it the default anywhere yet. No existing consumer has a workload MinIO
can't serve. It ships as an explicit second option, not a
platform-conditional default.

## Consequences

- Enabling `seaweedfs` with `topology: ha` and no `database` enabled
  fails validation with a plain-language message rather than silently
  running a non-HA filer under an HA label.
- No Operator/CRD tier means no `resources/common`-style "reference,
  not facet-wired" provisioning step the way MinIO has one — a
  SeaweedFS object-store is live (master/volume/filer/s3 all running)
  the moment the facet is enabled, not a dormant operator waiting for a
  Tenant. This is a materially different "cost of turning it on" than
  MinIO's today.
- Erasure-coding placement and rack/data-center-aware scheduling are out
  of scope for this ADR — this repo has no rack/DC node-labeling
  convention today, and `replication` codes alone cover the common case.
  Revisit if a deployment needs true erasure coding.
- S3-API compatibility gaps between SeaweedFS's gateway and MinIO's are
  real (some multipart/IAM-policy edge cases lag). Any existing MinIO
  consumer (Quickwit under `observability`) needs verification against
  SeaweedFS's gateway before being assumed portable across drivers.

## Alternatives considered

**Make SeaweedFS the default on non-cloud platforms.** No consumer today
has a workload MinIO can't serve, and this repo has no precedent of a
platform overriding a driver enum's default. Premature.

**Skip the `filer_store: postgres` dependency and ship HA on embedded
LevelDB anyway.** LevelDB does not support multiple writers; this would
either silently run a single-point-of-failure filer under an `ha` label
or require inventing a new embedded HA metadata store from scratch.
Reusing `database` costs one dependency and one `requires:` gate.

## References

- `contexts/_template/facets/addon-object-store.yaml`,
  `kustomize/object-store/install/minio/`,
  `kustomize/object-store/resources/common/` — the shipped `minio` driver
  this one sits alongside.
- `contexts/_template/facets/addon-database.yaml` — the
  `topology == 'ha'` gating pattern and the `database` capability this
  ADR's `filer_store: postgres` path depends on.
- SeaweedFS: [seaweedfs.io](https://github.com/seaweedfs/seaweedfs) —
  master/volume/filer/S3-gateway architecture, filer store backends.
