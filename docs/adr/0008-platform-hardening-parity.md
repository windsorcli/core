---
title: "ADR-0008: Platform hardening parity — disk/etcd encryption, audit logging, default-deny network policy"
description: "AWS and Azure default to KMS-backed encryption and audit logging; every self-managed Talos platform (Hetzner, vSphere, Hyper-V, Incus, Docker, metal) ships etcd and node disks unencrypted with no audit trail, and no platform has a cluster-wide network-policy default-deny baseline. Sequences three decisions to close the widest present/absent split in the platform table, and records the Hetzner static-credential fallback as an accepted, documented boundary rather than a gap needing a fix."
---

# ADR-0008: Platform hardening parity — disk/etcd encryption, audit logging, default-deny network policy

## Status

Proposed.

## Context

A platform-by-platform audit of every `platform-*.yaml` facet plus the
supporting Terraform found the widest present/absent split in the
repo, uniform across managed-cloud vs self-managed platforms rather than
random per-platform variance:

| Capability | AWS (EKS) | Azure (AKS) | Hetzner / vSphere / Hyper-V / Incus / Docker / metal (Talos) |
|---|---|---|---|
| Etcd/secrets-at-rest encryption | KMS-backed, default on (`terraform/cluster/aws-eks/variables.tf:316-332`) | N/A (managed etcd); node-disk CMK encryption default on (`terraform/cluster/azure-aks/variables.tf:349-352`) | **Absent everywhere** — no LUKS/`systemDiskEncryption` config in `config-talos.yaml` or any Talos platform facet |
| Node/volume encryption | Default on (`variables.tf:336-341`) | Default on (CMK disk encryption set) | Absent |
| API-server audit logging | Default on, includes `audit` log type (`main.tf:88-90`) | Diagnostic settings exist but `kube-audit` is excluded by default, only `kube-audit-admin` | **Absent everywhere** — no `--audit-log`/`--audit-policy` machine-config flags anywhere |
| Cluster-wide network-policy default-deny | Not enforced on any platform | | Only narrow, feature-scoped CiliumNetworkPolicies exist (Keycloak, gitops webhook, gateway UI, CoreDNS-etcd) — no baseline anywhere |

Separately, Hetzner falls back to a static `hcloud` API token Secret for
its CCM/CSI/DNS controllers (`platform-hetzner.yaml:292-353`), where AWS
and Azure get IRSA/Workload-Identity federation. This is architecturally
forced — Hetzner has no workload-identity primitive — not a gap this ADR
proposes to close; it's recorded below as an accepted, documented
boundary, the same way [ADR-0005](0005-secrets-store.md) documents
OpenBao's unseal key as a Terraform-state-held secret rather than
pretending a fix is pending.

Image signature verification (cosign/Kyverno `verifyImages`) and
namespace-level `ResourceQuota`/`LimitRange` defaults are also absent
everywhere, but uniformly so — no platform is worse than another — and
neither has a concrete consumer asking for it today. They're noted as
backlog, not sequenced into this ADR's decisions.

## Decision

### 1. STATE/EPHEMERAL partition encryption, static key, Terraform-generated

Every self-managed Talos platform gets `systemDiskEncryption` (LUKS2) on
the STATE and EPHEMERAL partitions by default, keyed by a static
passphrase. The passphrase is generated once by Terraform and held in
state, following the exact pattern already established for
[ADR-0005](0005-secrets-store.md)'s OpenBao unseal key and
`pki.private_ca`'s keypair — this is the fourth application of the same
"Terraform generates once, a facet places it" shape, not a new
mechanism. A per-platform override to a real KMS-backed key exchange
(where one exists) is a later, additive option, not required for parity.

### 2. API-server audit logging, shipped through the existing observability pipeline

Talos machine config gets `--audit-log-path`/`--audit-policy-file` set
by default, writing to a path the existing fluent-bit collection
(`telemetry`/`observability` addon) already tails — no new log sink,
reusing the pipeline every Talos platform already runs. Azure's
`kube-audit` exclusion is corrected to match AWS's default-on posture in
the same pass, so both managed clouds agree.

### 3. A cluster-wide Cilium default-deny baseline

A single default-deny `CiliumClusterwideNetworkPolicy` (ingress from
outside the cluster network) ships as part of the `cni` capability,
default on, with the existing narrow per-feature CiliumNetworkPolicies
(Keycloak, gitops webhook, gateway UI, CoreDNS-etcd) becoming the
explicit-allow exceptions to it rather than the only policies that
exist. A `requires:`-gated escape hatch lets a context turn it off in
plain language (*"cluster-wide network policy enforcement"*), not by
deleting the baseline policy by hand.

### 4. Hetzner's static credential — documented, not fixed

Hetzner's CCM/CSI/DNS controllers keep using a static `hcloud` API
token. No workload-identity-equivalent exists on Hetzner Cloud today, so
there is nothing to federate to. This ADR records the accepted-risk
posture explicitly rather than leaving it to be discovered by reading
`platform-hetzner.yaml` — revisit only if Hetzner ships an
identity-federation primitive.

## Consequences

- Closes the widest present/absent split in the platform table: every
  Talos-driven platform gains disk/etcd encryption and audit logging it
  has none of today, at parity with what AWS and Azure already default
  to.
- The default-deny baseline is the one decision with real regression
  risk — every existing narrow CiliumNetworkPolicy has to be re-verified
  as a correct, sufficient allow-rule under a default-deny posture,
  not just an additive rule under today's default-allow one.
- Static-passphrase disk encryption is a real but bounded improvement
  over no encryption at all — it protects data at rest against a lost or
  stolen disk, not against an attacker with access to the Terraform
  state backend. Worth stating plainly, the same way the OpenBao unseal
  key's Terraform-state exposure is stated in ADR-0005.
- Hetzner's static-credential posture remains exactly what it is today;
  this ADR changes nothing about it beyond writing it down as a
  deliberate boundary.

## Alternatives considered

**Per-platform KMS-backed disk encryption as the default, rather than a
static passphrase.** Matches cloud best practice on AWS/Azure but has no
equivalent on Hetzner, vSphere, Hyper-V, Incus, or metal — all of which
core supports today. A static Terraform-generated key is the one
mechanism available on every platform; a real KMS becomes a per-platform
opt-in later, not the default gating parity on infrastructure most of
this repo's platforms don't have.

**Ship the default-deny network policy as opt-in rather than default
on.** Leaves every context that doesn't explicitly turn it on exactly as
exposed as today, which defeats the point of a parity baseline. Default
on with an explicit opt-out matches how `policies.require_image_digest`
and friends already default to enabled.

**Attempt to fix Hetzner's static-credential posture with a
Kyverno-based workaround or a home-grown token-rotation job.** Invents
complexity to route around a real platform limitation rather than
naming it; nothing about a synthetic workaround changes the fact that
Hetzner Cloud has no IRSA/Workload-Identity equivalent to federate to.

## References

- `terraform/cluster/aws-eks/variables.tf:316-341`,
  `terraform/cluster/azure-aks/variables.tf:349-393` — the existing
  cloud-platform encryption/audit defaults this ADR brings Talos
  platforms to parity with.
- `contexts/_template/facets/config-talos.yaml`,
  `contexts/_template/facets/platform-hetzner.yaml`,
  `platform-vsphere.yaml`, `platform-hyperv.yaml`, `platform-incus.yaml`,
  `platform-docker.yaml`, `platform-metal.yaml` — the platforms this
  ADR's decisions 1-2 apply to uniformly.
- `kustomize/identity/resources/keycloak/cilium/ciliumnetworkpolicy.yaml`,
  `kustomize/gitops/resources/webhook/gateway/cilium/`,
  `kustomize/dns/install/coredns/etcd/network-policy.yaml` — the
  existing narrow CiliumNetworkPolicies decision 3 turns into explicit
  allow-rules under a default-deny baseline.
- [ADR-0005](0005-secrets-store.md), `contexts/_template/facets/addon-private-ca.yaml`
  — the Terraform-generate-once, facet-place pattern decision 1 reuses.
- Talos: [Disk Encryption](https://www.talos.dev/latest/talos-guides/configuration/disk-encryption/).
