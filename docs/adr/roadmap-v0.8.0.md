---
title: Release v0.8.0 — Planning & ADR Sequence
description: Seeds and sequences the ADRs that lead up to the v0.8.0 release. Living planning document, not an ADR.
---

# Release v0.8.0 — Planning & ADR Sequence

- Status: Drafting
- Date: 2026-08-04
- Deciders: Ryan VanGundy
- Purpose: Track the audit that pruned the prior release cycle's ADRs and plans, and sequence what's carried into v0.8.0. Each numbered ADR in this directory is authored separately.

## Why this release exists

Two things are driving v0.8.0 beyond the carried-forward gateway/secrets/
versioning work: Windsor Manager has started being built (a fleet-management
blueprint layered on core — Omni, Talos image factory, Cluster API, Keycloak,
OpenBao, Harbor, Velero) and is naming concrete things it needs from core;
and a first cross-platform hardening/completeness pass surfaced real,
grounded gaps in core's own story. Both are reflected in the ADR sequence
below rather than left as informal asks.

## Note on ADR/plan numbering and pruning (2026-08-04)

The prior cycle's ADRs (0001-0009) and plans were audited against the shipped codebase.

**Fully implemented, deleted:** ADR-0003 (layered kustomize `crds:`/`install:`/`resources:` tiers — `crds:` is a top-level entry in four facets, the tier syntax is live everywhere), ADR-0005 (`flux:` replacing `kustomize:` as the facet key — no facet uses the old key anymore), ADR-0008 (cluster identity and SSO — the `identity` capability, `addons.keycloak` removal, inferred Grafana/kube-apiserver SSO, and the client-secret copy-Job are all live and tested), and the plans `hetzner-support.md` (compute/CSI/LB/DNS all wired and tested) and `policy-tier-migration.md` (no `policy-base`/`policy-resources` references remain anywhere).

**Speculative, zero code, pruned to backlog notes below rather than carried forward as full documents:** ADR-0001 (tunnel as an independent subsystem), ADR-0002 (Cloudflare auth via static Secret), ADR-0006 (bring-your-own network/DNS — also blocked on an unstarted `cli`-side expression-evaluable `path:` field), the plan `cloudflare-proxy.md`, the plan `vercel-parity.md` (no Knative/buildpack code exists), and the plan `cloud-progressive-scaling.md` (basic pool autoscaling already exists independently of this plan; the multi-AZ/HA and security-tightening transitions it describes are untouched).

**Rejected, deleted:** the plan `blueprint-list-generation.md` — the motivating gap (Alertmanager notification routing) was solved with static per-driver schema fields instead; the doc says so itself.

**Superseded, deleted, with residual open items folded into backlog notes:** the plan `keycloak-idp.md` — its identity/SSO model is superseded by (now-deleted, now-shipped) ADR-0008, but two items it tracked are not yet addressed by any code: Keycloak database sizing/connection-scaling config, and realm reconciliation via `keycloak-config-cli` (today is one-shot import only).

**Carried forward from the prior cycle, renumbered 0001-0003, rescoped to what's actually left:**

| # | Title | What's left |
|---|---|---|
| [0001](0001-internal-external-gateways-and-dns.md) | Split external and internal gateways, DNS, and endpoints | All three milestones. A prior attempt (`feat/gateway-external-internal-split`) was never merged and isn't an ancestor of `main`; the running code is still the pre-ADR single-gateway model. |
| [0002](0002-cluster-secrets-management.md) | Cluster secrets — ExternalSecret materialization | The plain-`Secret` path (sensitive schema properties + facet `secrets:`/`data:` wiring) is shipped and live in five facets. Materializing the same entries as an `ExternalSecret` once ADR-0004 and ADR-0005 are both enabled remains. |
| [0003](0003-versioning-and-upgrade-contract.md) | Upgrade-path contract over bundled dependencies | The `breaking`→`minor` label-mapping fix is shipped. Autolabeling structural-dependency PRs and a Renovate policy that stops blanket-automerging Talos/`k8s-versions` remain. |

**New this cycle, driven by Windsor Manager's build-out and the hardening audit:**

| # | Title | Why |
|---|---|---|
| [0004](0004-external-secrets-operator.md) | External Secrets Operator addon | Formalizes [core#2284](https://github.com/windsorcli/core/issues/2284). Runtime secret sync every cluster wants, standalone or fleet. |
| [0005](0005-secrets-store.md) | secrets_store — OpenBao or an external Vault-API-compatible store | Formalizes [core#2285](https://github.com/windsorcli/core/issues/2285), extended with an `external` driver — the shape a downstream fleet cluster needs to read from Windsor Manager's shared OpenBao instead of self-hosting its own. |
| [0006](0006-object-store-seaweedfs.md) | SeaweedFS as a second `object_store` driver | A lighter-weight alternative to MinIO's Operator+Tenant split for platforms without cloud CSI economics. |
| [0007](0007-backup-restore-velero.md) | Backup and restore — Velero over `object_store` | Confirmed absent on every platform today; the single largest capability gap found. Also the prerequisite Manager's own-state backup (its ADR slot 0007) layers onto. |
| [0008](0008-platform-hardening-parity.md) | Platform hardening parity | Every self-managed Talos platform ships etcd/disk unencrypted and with no audit trail, where AWS/Azure default both on; no platform has a network-policy default-deny baseline. The widest present/absent split found in the cross-platform audit. |
| [0009](0009-crossplane-cloud-databases.md) | Crossplane — application-requested cloud databases | Formalizes [core#2515](https://github.com/windsorcli/core/issues/2515), scoped to one customer need: a Helm chart installed on top of core must be able to request a cloud-managed Postgres database without the customer authoring their own blueprint. |

**Going forward, `docs/adr/` is tracked in git, not gitignored, and there is no
more `docs/plans/`** (the plan carried from the prior cycle, karpenter
migration, is folded into this document below rather than kept as a
separate file — see Active work). ADRs are deleted and the sequence
restarts after every release; a carried-forward ADR should justify itself
against the next release's actual scope, not just against "this isn't
finished yet."

## Active work (not an ADR — a build in progress)

**Karpenter migration** (folded in from the deleted `docs/plans/karpenter-migration.md`).
Self-hosted Karpenter replaces AWS EKS managed node groups + cluster-autoscaler
(EKS Auto Mode is incompatible with Windsor's Cilium CNI); the portable `pools`
schema is redesigned to a Karpenter-native model; Azure converges on AKS Node
Auto-Provisioning. Status: PR 1 (Terraform substrate — Karpenter IAM, node
role/instance profile, SQS spot-interruption queue) landed in
`terraform/cluster/aws-eks/karpenter.tf`, gated behind `enable_karpenter`, but
no facet or context sets that variable, so it's unreachable through the
blueprint today. PRs 2-4 (Karpenter deployment + NodePool generation from a
redesigned `pools` schema, cluster-autoscaler removal, Azure NAP convergence)
have not started; cluster-autoscaler and the count/min/max `pools` schema are
both still fully in place. This will get its own ADR once the NodePool schema
redesign — the load-bearing decision — needs to be written down; until then
it's tracked here as in-progress work, not a design question.

## Flagged for investigation: Talos upgradeability

Not an ADR yet — grounded enough to name as a real gap, not grounded enough
to write a decision. Needs platform-by-platform investigation and testing
before it can become one.

ADR-0003 named the docker case (container-mode Talos has no in-place
upgrade, so a `talos_version` bump forces a control-plane rebuild) as the
one verified instance of a broader problem. It's broader than that single
case:

- **The only in-place upgrade path in the repo is `cluster/talos/extensions`**
  (`null_resource.upgrade_controlplane`/`upgrade_worker`, controlplane-first,
  serialized via `parallelism = 1`, driven by `windsor upgrade node` which
  sends the upgrade, waits for reboot, and verifies health). It's wired by
  exactly one facet, `option-storage.yaml`, gated on
  `cluster.storage.driver == 'longhorn'` — the default `openebs` driver
  never routes through it.
- **Everywhere else, a `talos_version` bump does one of two things, neither
  of which is a real in-place upgrade:**
  - **Forces full node replacement** on docker (`talos_version` is the
    container image tag — [main.tf](../../terraform/compute/docker/main.tf))
    and hcloud (`talos_version` is baked into the Image Factory `image_url`
    — [main.tf:140](../../terraform/compute/hcloud/main.tf#L140)).
  - **Silently drifts** on vsphere/hyperv/incus: `talos_version` only feeds
    `data.talos_machine_configuration` (the generated machine config), not
    the VM's boot image/ISO/template, which is selected independently. The
    machine config says the new version; the running node's installed Talos
    does not change.
- Even the extensions path itself only fires when `var.extensions` is
  non-empty (`length(var.extensions) > 0 ? "factory.talos.dev/installer/...:v${var.talos_version}" : ""`
  — [extensions/main.tf:47](../../terraform/cluster/talos/extensions/main.tf#L47)),
  so a longhorn cluster with no other extensions still gets the upgrade
  path; an openebs cluster gets nothing.

There's real prior art to build from — `windsor upgrade node`'s
send-upgrade/wait/health-check sequencing and the controlplane-first
serialized ordering are already correct patterns, just scoped too narrowly.
The actual design work (extending that mechanism to every platform, or
accepting node-replacement as the contract on docker/hcloud specifically and
making that explicit and safe, versus fixing the silent-drift case on
vsphere/hyperv/incus, plus etcd-quorum-safe sequencing, k8s version skew
rules, and rollback) needs real investigation and testing per platform
before it's decidable — this is a placeholder for that work, not the
answer.

## Backlog (pruned or considered, no ADR carried)

From the prior cycle's pruning:

- **Tunnel as an independent subsystem** (Cloudflare Tunnel first, ngrok/Tailscale Funnel/Inlets later) — a top-level schema concept and its own namespace, fronting the external gateway once ADR-0001's split lands. Zero code.
- **Cloudflare auth via static in-cluster Secret** — the only viable auth model until ADR-0005's `external`/vault-compatible driver covers it too. Depends on the tunnel work above.
- **Bring-your-own network and DNS zone** — sibling `terraform/<layer>/<project>-data` modules for landing in a pre-existing VPC/VNet or hosted zone, selected by an expression-evaluable `path:` field. Needs a `cli`-side change (`collectTerraformComponents` doesn't evaluate `Path` as an expression today) before any core-side work can start.
- **Vercel parity** — a self-hosted Vercel-like experience (Knative + in-cluster buildpacks + an apps blueprint layered on core). No code exists.
- **Cloud progressive scaling** — a documented cheap→elastic→HA→hardened upgrade path for AWS/Azure deploys, beyond the pool-level autoscaling that already exists.
- **Keycloak database sizing/connection scaling** — `identity.keycloak` has no storage/resource or connection-pooler config yet.
- **Keycloak realm reconciliation** — realm config is one-shot import only; no `keycloak-config-cli`-style continuous reconciliation.
- **ADR-0008 (deleted, identity)'s own fast-follow items** (not gaps, just not yet started): MinIO console SSO, gateway edge auth via the identity provider, and non-Keycloak `oidc` endpoint-derivation assumptions for providers that don't follow the Keycloak URL convention.

From this cycle's manager/hardening review, considered and not carried as an
ADR — either not urgent enough or not grounded enough yet:

- **Image signature verification** (cosign/sigstore via Kyverno `verifyImages`) — no consumer asking for it today, but a small, low-risk follow-on once policy work next touches the `policy` addon; `require-image-digest` already gives it a digest to verify against.
- **Container registry mirror / pull-through cache** — needed for Harbor's disconnected-install story, but Manager's own roadmap explicitly defers Harbor itself ("needed for the disconnected install, not for a first cut that pulls from upstream registries"). Premature until an airgapped install is actually being built.
- **Service mesh / mTLS, multi-tenancy primitives, FinOps/cost visibility, egress control** — surveyed and found ungrounded: no addon, ADR, or manager reference names any of these as a real near-term need. Not carried.
