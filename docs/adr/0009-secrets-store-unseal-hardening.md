---
title: "ADR-0009: OpenBao unseal hardening on platforms without a cloud KMS"
description: "Is the generic bootstrap Job's Shamir-share-in-a-Secret answer durable enough long-term on Hetzner, vSphere, Hyper-V, Incus, and metal, which have no platform-native KMS to layer cloud auto-unseal on top of? Proposed direction: accept it for v0.8.0, revisit once Windsor Manager's fleet model gives every downstream cluster a shared, already-unsealed instance to point Transit auto-unseal at."
---

# ADR-0009: OpenBao unseal hardening on platforms without a cloud KMS

## Status

Proposed. Narrower follow-on to [ADR-0005](0005-secrets-store.md) §2,
which covers how every platform unseals at all (a generic in-cluster
bootstrap Job) and how AWS/Azure additionally auto-unseal via their native
KMS. This ADR asks whether the generic answer is good enough long-term on
the platforms that can't layer anything on top of it.

## Context

ADR-0005's bootstrap Job (`kustomize/secrets/install/openbao/bootstrap/`)
runs a one-time `bao operator init` and, for Shamir seals, resubmits the
stored share after every restart, on every platform. On AWS and Azure that
recurring step becomes a no-op because OpenBao runs a cloud KMS auto-unseal
driver instead of Shamir.

Hetzner, vSphere, Hyper-V, Incus, and metal have no equivalent — no
platform-native KMS to hand the unseal key to. On those platforms the
bootstrap Job's Shamir share, sitting in a plain `system-secrets-store`
Secret, *is* the root-of-trust for the whole store, permanently, not just
during an interim period before something better ships.

## Decision

Accept it for v0.8.0. Same posture ADR-0005 already accepts as the
starting point for AWS/Azure before this work landed — a plain Secret
holding sensitive material, scoped by RBAC, not a KMS-backed answer.
Whoever can read Secrets in `system-secrets-store` can unseal and fully
access the store; that has always been true for the driver's own root
token too, and configuring a scoped, non-root auth method for ESO to use
instead is already separate, not-yet-scoped work regardless of unseal
strategy.

The identified hardening path: **Transit auto-unseal against a second,
already-unsealed OpenBao instance**, once one exists to point at. Windsor
Manager's fleet model (referenced in ADR-0005's context) runs one shared
OpenBao on the management cluster for exactly this kind of purpose — a
downstream Hetzner/vSphere/metal cluster's own self-hosted OpenBao could
Transit-unseal against Manager's instance instead of holding a Shamir
share locally at all. That instance doesn't exist as a standalone
capability today, so this isn't buildable yet — revisit once it is.

## Alternatives considered

**Real HSM/PKCS11 support now.** A hardware dependency this blueprint has
no reason to assume exists on a Hetzner box, a vSphere VM, or a bare-metal
node it doesn't control the provisioning of. Out of scope for a portable
blueprint; an operator running their own HSM already has the `external`
secrets-store driver as an escape hatch (point at an instance they manage
themselves).

**Building Transit auto-unseal now, against a second self-hosted OpenBao
stood up solely for this purpose.** Pure overhead for a single-cluster
install — bootstrapping a second instance just to unseal the first adds
an unseal problem for the second instance without removing the one for
the first. Only pays off once a shared instance already exists for other
reasons, which is exactly Manager's fleet model.

**A k8s Secret in a more restrictive namespace, or split across multiple
Secrets.** Doesn't change the fundamental answer — whoever has RBAC read
access still has the key. Not worth its own decision; the real lever is
removing the key from Kubernetes-readable storage entirely, which is what
Transit auto-unseal against an external instance actually does.

## References

- [ADR-0005](0005-secrets-store.md) — the bootstrap Job and AWS/Azure
  auto-unseal this ADR is scoped against.
- `kustomize/secrets/install/openbao/bootstrap/` — the generic Job/CronJob
  this ADR evaluates the long-term posture of.
- OpenBao Transit auto-unseal: [openbao.org](https://openbao.org/docs/configuration/seal/transit/).
