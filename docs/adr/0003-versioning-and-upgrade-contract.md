---
title: "ADR-0003: Upgrade-path contract over bundled dependencies — autolabeling and Renovate policy"
description: "core bundles many dependencies (Talos, k8s-versions, CRD-vendored charts) that Renovate updates automatically and release-drafter buckets as patch; some of those are structural — any version change forces a rebuild regardless of the size of the upstream bump — so a nominal patch release can silently break the 0.X.x -> 0.X.(x+1) upgrade contract. Adds autolabeling plus Renovate policy keyed to the same structural files CI already treats specially."
---

# ADR-0003: Upgrade-path contract over bundled dependencies — autolabeling and Renovate policy

## Status

Proposed. Revised (2026-08-04): the label-mapping fix (`breaking` resolves
minor, not major) already shipped — `.github/release-drafter.yml`'s
`version-resolver` matches this ADR's original decision 1. This ADR is
rescoped to the two pieces still open: autolabeling structural-dependency
PRs, and a Renovate policy that stops blanket-automerging them.

## Context

### 0ver: major is reserved for a deliberate GA cut

core and cli are both pre-1.0. Neither commits to strict SemVer today. The
scheme is 0ver: `1.0.0` is a deliberate GA milestone, not a value that falls
out of a label on some PR; until then a breaking change increments minor
(`0.7.0` → `0.8.0`), not major. `release-drafter.yml`'s `version-resolver`
in both repos already reflects this (`breaking` maps to `minor`, `major` is
label-gated only) — see Shipped below.

### The bundled-dependency problem is a separate, sharper issue

core also bundles many third-party dependencies — Helm charts, Terraform
providers, `k8s-versions` (aks/eks Kubernetes versions), Talos — and Renovate
updates most of them automatically. Consumers reasonably expect the same
kind of contract for those bundled deps that they'd expect from core itself:
upgrade to the latest patch, then to the latest next minor, and it works.

That expectation is already violated in one concrete, verified case.
`ci.yaml` (`talos_version_of`, `ci.yaml:236-248`) diffs
`contexts/_template/facets/config-talos.yaml`'s `talos_version` between base
and head, and if it changed — **at any granularity, not just a minor
bump** — skips the in-place upgrade test entirely, because container-mode
Talos has no in-place upgrade: the control plane must be rebuilt. That PR
still only carries whatever label Renovate attached (`dependencies`), which
`version-resolver.patch` picks up. So a nominal `0.7.3` → `0.7.4` release can
embed a change that forces a cluster rebuild — exactly what a patch bump is
supposed to rule out.

The risk here isn't proportional to how far upstream moved. For most bundled
deps, ordinary patch/minor-is-safe expectations hold. For a smaller set —
Talos being the clearest, verified case — the disruption is structural and
binary: any version change is disruptive, independent of upstream's own
versioning discipline. `k8s-versions` (aks/eks) and CRD-vendored charts
(charts hoisted to vendor scope because `helm show crds` returns
install-only CRDs) are the other known candidates, though unlike Talos this
hasn't been verified against a CI check the way `talos_version_of` was.

Today nothing distinguishes "Renovate bumped a Docker digest" from "Renovate
bumped the Talos node image" at the release-labeling layer. Both land as
`dependencies` → `patch`.

### Shipped: the label-mapping fix

`.github/release-drafter.yml`'s `version-resolver` already maps `breaking`
to `minor` and reserves `major` for the `major` label alone. `major` is now
opt-in only — applied by hand the day a `1.0.0` cut is actually intended —
rather than something a routine breaking-change PR triggers on its own.
What remains is distinguishing a structural dependency bump from an
ordinary one at the labeling layer.

## Decision

### 1. Structural dependency bumps are autolabeled, not left to Renovate's own labels

core adds a release-drafter `autolabeler` rule matching the same files
`ci.yaml` already treats as structural (starting with
`contexts/_template/facets/config-talos.yaml`; extended to the
`k8s-versions` dep file and CRD-vendor paths as those are confirmed).
Any PR touching one of these files — Renovate-authored or not — gets an
`upgrade-impact` label automatically. That label maps into
`version-resolver.minor` and gets its own changelog category, so it's
visible in release notes instead of folded into the collapsed
"Dependencies" group.

This reuses the detection `ci.yaml` already performs rather than inventing a
second source of truth, and doesn't depend on Renovate's package list
staying exhaustive — a new structural dependency is covered as long as its
version lives in a file this rule watches.

### 2. Renovate stops blanket-automerging structural dependencies

A `packageRule` in `.github/renovate.json` matches the known structural
dependencies (Talos, `k8s-versions`) and:

- disables automerge, so a human sees the PR before it merges;
- applies the `upgrade-impact` label directly, as a second signal alongside
  the autolabeler;
- optionally sets `minimumReleaseAge` so a brand-new upstream release isn't
  pulled in immediately.

Non-structural dependencies (GitHub Actions digests, most Go modules, Docker
digest-only pins, most Helm chart bumps) keep today's automerge behavior —
this decision narrows the exception, it doesn't remove blanket automerge.

### 3. Release cadence follows from the contract, not the other way around

`0.X.x` → `0.X.(x+1)` is only a meaningful promise if consecutive releases
stay close enough together that nobody skips over an accumulation of
`upgrade-impact` changes between them. `release-drafter.yaml` currently only
maintains a draft on push to `main`; nothing publishes it. This ADR treats
"decide a publish cadence" (scheduled, e.g. weekly, or triggered whenever an
`upgrade-impact`/`minor` PR merges) as a required follow-up, not a nice-to-have
— left as an open decision below rather than settled here, since it's an
operational choice, not an architectural one.

## Consequences

- **`breaking` is safe to apply liberally again** — it no longer forces an
  unwanted major cut, which was the original complaint that prompted this
  ADR.
- **`major` needs a human to apply it on purpose.** No automated path
  (Renovate, autolabeler, or otherwise) should ever attach `major` — if one
  does by accident, that's a bug in this scheme, not a feature of it.
- **Renovate PRs for Talos/`k8s-versions` would require manual merge.**
  Slower than today's full automerge, but matches the fact that CI already
  can't fully validate these paths (the upgrade test is skipped, not passed).
- **The structural-file list needs upkeep.** If a new bundled dependency
  turns out to be rebuild-forcing the way Talos is, both the `ci.yaml`
  detection and this ADR's autolabeler/Renovate rule need a matching entry.
  Nothing enforces that they stay in sync today.
- **Publish cadence is still unresolved** (see Open questions) — this ADR
  fixes the labeling/detection side of the contract but doesn't by itself
  guarantee releases are cut often enough to keep any single upgrade step
  small.

## Open questions

- **Publish cadence.** Scheduled (e.g. weekly) vs. triggered by any
  `minor`/`upgrade-impact` merge vs. left manual. Not settled here.
- **CI enforcement, not just detection.** `talos_version_of` today skips the
  upgrade test silently on a structural change; it could instead fail the
  PR when the structural file changed but `upgrade-impact` isn't present,
  closing the loop between "CI knows this needs a rebuild" and "the release
  is labeled accordingly." Left as a fast-follow, not required for this ADR.
- **Full structural-file list.** Only Talos is verified against an existing
  CI check. `k8s-versions` and CRD-vendor paths are plausible candidates but
  unverified — confirm before adding them to the autolabeler.
- **`enforce-pr-labels.yaml` lists `minor`/`patch` as accepted labels**, but
  `version-resolver` has never had a `minor`/`patch` label mapping of its
  own (only `major`/`breaking`/`feature`/the patch-bucket list) — a PR
  labeled bare `minor` silently falls through to `default: patch`. Whether
  to add explicit `minor`/`patch` label mappings is a small follow-up,
  orthogonal to this ADR's `breaking`/`upgrade-impact` changes.

## Alternatives considered

- **Leave `breaking` under `major`, tell people not to use it carelessly.**
  Relies on PR-time discipline to not trigger an unwanted GA cut; the
  incident that prompted this ADR is exactly that discipline failing.
- **Drop the `breaking` label entirely, rely on `minor` alone.** Loses the
  changelog signal that a given minor release contains a breaking change —
  `breaking` should still surface in release notes, it just shouldn't drive
  version resolution to major.
- **Tag structural dependencies via Renovate `matchPackageNames` only, no
  autolabeler.** Fragile: Renovate's package list has to independently track
  every structural dependency, whereas file-path autolabeling piggybacks on
  the same watch list `ci.yaml` already needs to maintain for its own
  detection.
- **Bump core's own minor version automatically whenever a structural
  dependency changes, skipping the label step.** Would need release-drafter
  (or a replacement) to read file diffs directly rather than PR labels,
  a larger change than this ADR's scope; the label indirection also keeps
  the signal visible to humans reviewing the PR, not just to tooling.

## References

- `.github/release-drafter.yml` (core and cli) — the shipped
  `version-resolver` mapping `breaking` to `minor`.
- [ci.yaml:236-248](../../.github/workflows/ci.yaml#L236-L248)
  (`talos_version_of`) — the verified structural-dependency detection this
  ADR's autolabeler reuses.
- `.github/renovate.json` — current blanket automerge `packageRule`s this
  ADR narrows for structural dependencies.
- `.github/workflows/enforce-pr-labels.yaml` — the required-label check
  referenced in Open questions.
