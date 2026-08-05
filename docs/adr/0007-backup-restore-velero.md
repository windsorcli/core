---
title: "ADR-0007: Backup and restore — a Velero addon over the existing object_store capability"
description: "core has no backup capability on any platform today — confirmed absent repo-wide (no velero, restic, or CNPG barmanObjectStore config anywhere). Adds a top-level backup capability installing Velero, targeting the existing object_store addon as its object-storage backend rather than provisioning a second one. Scoped to workload PVCs and CNPG in this ADR; Manager's own state (Omni's etcd, the secrets backend) is fleet-only and out of scope."
---

# ADR-0007: Backup and restore — a Velero addon over the existing `object_store` capability

## Status

Proposed.

## Context

No platform, cloud or self-hosted, has any backup capability today —
confirmed by a repo-wide search: no `velero`, `restic`, or
`barmanObjectStore` anywhere. `kustomize/demo/resources/database/cluster.yaml`
sets a CloudNativePG `Cluster`'s instances/storage/monitoring with no
`backup:` block at all. For a blueprint whose stated goal is a coherent,
production-usable platform across providers, this is the single largest
capability gap found, and it's uniform — equally absent everywhere,
rather than inconsistent between platforms the way encryption or audit
logging are.

Windsor Manager's own roadmap names this directly, for its own state:
*"Backup and restore for Omni's etcd, the secrets backend, and the
databases. What Velero covers and what it can't"* (manager
`docs/roadmap-v0.1.0.md`, ADR slot 0007). That is fleet-only scope
(Omni, OpenBao, Manager's own CNPG instances) and stays Manager's to
decide. What core owns is the same capability for a single cluster's
own workloads — the prerequisite Manager's Velero install layers onto,
per the layering rule already established (`manager` ADR-0001: "if a
single cluster would also want the capability, it belongs in Core").

The `object_store` addon already ships an S3-compatible backend
(MinIO, soon optionally SeaweedFS per [ADR-0006](0006-object-store-seaweedfs.md))
built for exactly this kind of consumer — Velero's object-storage plugin
needs nothing more than an S3-compatible endpoint and credentials.

## Decision

### 1. A top-level `backup` capability, Velero as the driver

```yaml
backup:
  enabled: false
  driver: velero
  schedule: "0 2 * * *"
  retention: "720h"        # 30 days
```

Top-level, matching `identity`/`database`/`object_store`.

### 2. Targets the existing `object_store` addon, not a second bucket layer

Velero's `BackupStorageLocation` points at the cluster's own
`object_store` addon (whichever driver — `minio` or `seaweedfs` — is
enabled), using the same S3-compatible endpoint and credential pattern
consumers already use. `backup.enabled == true` requires
`object_store.enabled == true`; the facet's `requires:` gate says so in
plain terms — *"backup needs the object storage service enabled"* — not
in terms of `BackupStorageLocation`/plugin internals. Velero does not
provision its own object storage.

### 3. Scope: workload PVCs and CloudNativePG, not Manager's fleet state

This ADR covers what a single cluster needs for its own workloads:
- **Volume snapshots**, via Velero's CSI plugin, for any PVC-backed
  workload.
- **CloudNativePG**, via CNPG's own `barmanObjectStore`/plugin backup
  mechanism, configured to point at the same `object_store` backend —
  not through Velero's generic PVC snapshot path, which is the wrong
  tool for a running Postgres instance.

Omni's etcd, the secrets store's own data, and Manager's own databases
are fleet-only concerns; per the same layering rule, that's Manager's
ADR to write, over the top of the capability this ADR ships.

### 4. Install-only, off by default

A `flux:` system installing Velero (and its CSI plugin) — no CRs of its
own beyond the operator's, matching how `addon-database` and
[ADR-0004](0004-external-secrets-operator.md) ship. `Schedule`/`Backup`
CRs are the resources tier, generated from `backup.schedule`/`retention`.

## Consequences

- Every cluster gets the same backup mechanism regardless of platform —
  no cloud-specific snapshot API wiring (EBS snapshots, Azure Disk
  snapshots) needed as a separate path, since Velero's CSI plugin already
  abstracts that.
- CNPG backup is configured through CNPG's own mechanism, not Velero's
  PVC snapshot path — a running database needs a consistent dump/WAL
  archive, not a filesystem-level snapshot of its data directory.
- `object_store` moves from "nice for demo workloads" to "prerequisite
  for backup" — enabling `backup` without `object_store` fails
  validation rather than silently having nowhere to write.
- This ADR does not cover Manager's own state (Omni, the secrets store).
  That remains Manager's to design, consuming this capability the same
  way it consumes `identity`/`database` today.

## Alternatives considered

**Provision a dedicated bucket/store just for backups, separate from
`object_store`.** Doubles the object-storage surface for no real
benefit — `object_store` already exists as a general-purpose
S3-compatible backend, and Velero needs nothing beyond that contract.

**Route CNPG backup through Velero's generic PVC snapshot path.**
Filesystem-level snapshots of a live Postgres data directory are not a
consistent backup without additional coordination Velero doesn't
provide for databases; CNPG's own backup mechanism (WAL archiving,
`barmanObjectStore`) is built for exactly this and already exists
upstream.

**Cover Manager's fleet state (Omni's etcd, the secrets store) in this
ADR.** Out of altitude — a single cluster never needs to back up another
cluster's fleet-management state; that's Manager's own ADR to write, the
same layering split already drawn for identity and secrets.

## References

- `kustomize/database/install/cloudnativepg/`,
  `kustomize/demo/resources/database/cluster.yaml` — the CNPG install
  this ADR's database backup path configures.
- [ADR-0006](0006-object-store-seaweedfs.md),
  `contexts/_template/facets/addon-object-store.yaml` — the backend this
  addon targets.
- `manager` `docs/roadmap-v0.1.0.md` (ADR slot 0007, "Manager's own
  state") — the fleet-only scope this ADR explicitly excludes.
- `manager` `docs/adr/0001-layering-on-core.md` — the "if a single
  cluster would also want it, it belongs in core" rule this ADR follows.
- Velero: [velero.io](https://velero.io) — CSI plugin, `BackupStorageLocation`.
