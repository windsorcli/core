---
title: "ADR-0010: A single OCI registry mirror for Helm charts, images, and Terraform providers"
description: "Adds a top-level registry_mirror capability that redirects every Helm chart source, node-level image pull, and Terraform provider install through one operator-supplied OCI endpoint. The mirror is assumed to already exist and be populated; Windsor's job is generating an accurate manifest of what it needs to hold and pointing every consumer at it, not standing it up or filling it. Vendored content (CRDs, Grafana dashboards) and the blueprint's own Terraform/Kustomize source ride along inside the blueprint's own OCI artifact and need no separate mirroring."
---

# ADR-0010: A single OCI registry mirror for Helm charts, images, and Terraform providers

## Status

Proposed.

## Context

Today, registry mirroring exists only for local dev: `docker.registries`
(`contexts/_template/schema.yaml`) drives per-upstream pull-through cache
containers in `terraform/workstation/docker`/`incus`, and
`option-workstation.yaml` reshapes their output into Talos
`machine.registries.mirrors` entries, one per upstream host. This is gated
to `platform in [docker, incus]` — every production platform (metal,
hetzner, vsphere, hyperv, aws-eks, azure-aks) has no registry mirror
config at all. `docs/adr/roadmap-v0.8.0.md`'s backlog explicitly deferred
a registry mirror as premature, "needed for the disconnected install, not
for a first cut that pulls from upstream registries." That install is now
being built.

**The mirror is assumed to exist and be populated already.** Windsor
doesn't stand it up, doesn't run write traffic against it, and doesn't
prescribe pull-through caching versus a scheduled push — an operator
populates it however their environment requires, working from a manifest
Windsor produces. This ADR is about making every consumer point at one
endpoint, not about the registry itself.

A single mirror setting has to redirect several structurally different
pull paths, each with its own current wiring:

1. **Flux HelmRelease chart sources.** 28 `HelmRepository` resources
   (`kustomize/*/install/*/helm-repository.yaml`) point at classic
   `https://` chart-index URLs, one at a time. One more
   (`kustomize/gateway/install/envoy/helm-repository.yaml`) is already
   `type: oci`, `url: oci://docker.io/envoyproxy`. One HelmRelease
   (`kustomize/observability/install/fluentd/helm-release.yaml`) sources
   its chart from a `GitRepository` subpath instead. Every URL is a
   literal, hardcoded per file.
2. **Container images those charts deploy.** Referenced inline in
   HelmRelease `values:` as `image: repo:tag@sha256:digest`, enforced by
   the Kyverno `require-image-digest` `ClusterPolicy`
   (`kustomize/policy/resources/kyverno/require-image-digest/`), which
   exempts the flux-operator namespace.
3. **Flux's own bootstrap**, installed by Terraform before Flux exists to
   reconcile anything (`terraform/gitops/flux/main.tf`): two
   `helm_release` resources both pull `oci://ghcr.io/controlplaneio-fluxcd/charts`,
   hardcoded with no repository variable. The `flux-instance` release's
   values also set `instance.distribution.registry = "ghcr.io/fluxcd"` —
   Flux's own first-party knob for where its controller images come
   from, likewise hardcoded.
4. **Node-level image pulls** (kubelet/containerd). Wired today only for
   Talos platforms, only from workstation, via the per-host
   `machine.registries.mirrors` map above. Talos itself supports a
   catch-all `mirrors["*"]` entry with `overridePath` and a
   `registries.config` block for TLS/auth per mirror endpoint — unused
   in the current code, which enumerates hosts instead.
5. **Terraform provider binaries.** 41 `required_providers` blocks across
   `terraform/**` resolve providers from `registry.terraform.io` at
   `terraform init` time — a different distribution protocol from OCI
   entirely (provider zip archives over Terraform's own registry API,
   not `docker`/OCI manifests).

`kustomize/crds/sources.yaml` (`task crds`) and
`kustomize/observability/resources/grafana/dashboards/*/source.yaml`
(`task dashboards`) vendor CRDs and dashboard JSON from upstream at
dev/CI time, straight into git. **This ADR doesn't need to mirror
either.** The blueprint itself is moving to distribution as an OCI
artifact — Flux's blueprint source becomes an `OCIRepository` pulling
from the same registry this ADR configures, in place of the
`GitRepository` `terraform/gitops/flux/main.tf` currently notes ("windsor
CLI races the operator when it applies the blueprint GitRepository").
Once the blueprint ships as one OCI artifact, every vendored file —
CRDs, dashboards, and the Terraform module source itself — travels
inside it. Nothing needs a second copy on the mirror.

**Prior art**: the unmerged branch `feature/mirror` (`a4cecc38`, stale,
959 commits behind `main`) prototyped this for paths 1 and 4 — a
`cluster.mirror` string and `workstation.services.mirror` toggle, Flux's
own `${var:=default}` envsubst fallback syntax applied to every
`helm-repository.yaml` so an inactive mirror leaves each chart's original
URL untouched, and a Talos `overridePath: true` scheme that namespaces
every upstream under one path (`/v2/<registry-key>`) on a single
container. Its `mirror` container was a bare, unpopulated registry — no
population design existed. It never touched path 3 (Flux's own
bootstrap) or path 5 (Terraform providers).

**EKS/AKS** don't have a per-node containerd hook the way Talos machine
config does — managed node groups don't expose an equivalent config
surface. The idiomatic cloud-native answer is a registry-side
pull-through cache in front of the same upstream (ECR pull-through cache
rules, ACR cache rules), with pulls simply addressed at the cache
endpoint. That's the cloud provider's own mirror feature, not something
Windsor configures on the node — out of scope here (§ Non-goals).

## Decision

### 1. A top-level `registry_mirror` capability

```yaml
registry_mirror:
  enabled: false
  url: ""          # host:port, e.g. mirror.internal:5000
  insecure: false  # plain HTTP or self-signed TLS
```

Top-level, matching `object_store`/`identity`/`database`, not nested
under `cluster` — the setting governs Terraform's Flux bootstrap and
Terraform provider installation in addition to Talos machine config, so
it outgrows a `cluster.*` home. `url` is empty by default: on workstation
platforms (`docker`, `incus`) with `enabled: true` and no explicit `url`,
a local single-container mirror is stood up the same way
`workstation.services.mirror` did in `feature/mirror` — a dev
convenience, unrelated to how a real operator populates a real mirror.
Everywhere else, `url` names an endpoint this ADR assumes already exists
and already holds what's needed.

### 2. Helm chart sources collapse to one OCI path

Every `helm-repository.yaml` — classic `https://` and the one already-OCI
entry alike — gets the same three fields, using Flux's envsubst fallback
syntax so an inactive mirror is a no-op:

```yaml
spec:
  type: ${helm_repo_type:=default}
  url: ${helm_registry:=https://helm.cilium.io}
  insecure: ${helm_repo_insecure:=false}
```

`platform-base.yaml` resolves the three substitutions from
`registry_mirror`:

```yaml
helm_repo_type: "${registry_mirror.enabled == true ? 'oci' : ''}"
helm_registry: "${registry_mirror.enabled == true ? 'oci://' + registry_mirror_effective.url + '/charts' : ''}"
helm_repo_insecure: "${registry_mirror.enabled == true ? string(registry_mirror.insecure ?? false) : ''}"
```

This answers the "must be OCI-only, not both" requirement directly: once
a mirror is active, `type` is `oci` for every chart regardless of its
original repository style, and every chart resolves under one flat
`oci://<mirror>/charts/<chart-name>` namespace on the mirror. The
`GitRepository`-sourced fluentd chart is unaffected; git isn't OCI and
stays out of scope for this ADR.

### 3. Flux's own bootstrap gets the same override

`terraform/gitops/flux/main.tf`'s two hardcoded
`oci://ghcr.io/controlplaneio-fluxcd/charts` repository strings and the
`instance.distribution.registry` value become variables
(`flux_operator_chart_repository`, `flux_distribution_registry`),
defaulting to today's literals. The `gitops` facet resolves them from
`registry_mirror` the same way it resolves every other Terraform input,
so the chart that installs Flux and the images Flux's own controllers
run are on the mirror path from the first apply, not left as an
unmirrored exception.

### 4. Talos node pulls use one catch-all mirror, not a per-host map

`config-talos.yaml` gains a `registry_mirror_active` local
(`registry_mirror.enabled == true`) and, when true, injects Talos's
native wildcard mirror instead of enumerating upstream hosts:

```yaml
machine:
  registries:
    mirrors:
      "*":
        endpoints: ["http://${registry_mirror_effective.url}"]
        overridePath: true
    config:
      "${registry_mirror_effective.url}":
        tls: { insecureSkipVerify: ${registry_mirror.insecure ?? false} }
```

This rides the same `common_config_patches` plumbing every other Talos
patch already uses — no Terraform module change. It's mutually exclusive
with the existing per-host `docker.registries` pull-through map: when
`registry_mirror.enabled` is true, `option-workstation.yaml`'s
per-registry containers and Talos entries are skipped, on any platform,
via one gate. `docker.registries` remains the zero-config workstation
default when no mirror is configured — this ADR doesn't touch that path.

### 5. Terraform providers ride the same OCI endpoint

A Terraform provider is a zip archive fetched over Terraform's own
registry protocol, not an OCI manifest — Talos/Flux/containerd's mirror
mechanisms don't apply to it. But an OCI registry isn't limited to
images and Helm charts; anything can be pushed to one as a generic
artifact (the same technique `oras` and Helm's own OCI chart support
both rest on). Rather than stand up a second, protocol-different mirror
server, provider packages are addressed as generic OCI artifacts on the
**same** `registry_mirror.url`, keyed by the coordinates every
`required_providers` block already carries:

```
oci://<registry_mirror.url>/providers/<hostname>/<namespace>/<type>/<version>/<os>_<arch>
```

Consuming this is CLI-repo work, not `core`'s: before `terraform init`,
the `windsor` CLI pulls the providers a module needs from that path into
a local directory and points Terraform at it via a generated
`provider_installation { filesystem_mirror { path = ... } }` block
(`TF_CLI_CONFIG_FILE`). `core`'s side of the contract is the addressing
convention above and the manifest in §6 — the fetch-and-rewire step
belongs where `TF_CLI_CONFIG_FILE` is already written today (nowhere in
`core`, which has no CLI wrapper of its own).

### 6. Windsor's job stops at the manifest

Windsor generates an inventory of everything the blueprint needs from
the mirror — every Helm chart name/version, every image reference with
its digest, every Terraform provider address/version/platform — from
what's already in git: `helm-repository.yaml` + HelmRelease `chart.spec`
for charts, `image:`/`tag@sha256` fields across HelmRelease values for
images, `required_providers` blocks for providers. A `task mirror`-style
generator (alongside the existing `task crds`/`task dashboards`
convention) emits this as a standard SBOM (CycloneDX), the format most
registry-populate and scanning pipelines already consume, so an
operator's existing tooling — whatever it is — can resolve it against
their mirror. How they turn that list into a populated registry (lazy
pull-through cache, a scheduled sync job, a manual push) is theirs to
choose; Windsor doesn't run that step and doesn't require any particular
mechanism.

## Consequences

- One flag switches every Helm chart source to OCI uniformly, closing
  the "HelmRepository-or-OCI, never both" requirement without touching
  the ~29 files' chart names or versions.
- Talos-based platforms (docker, incus, metal, hetzner, vsphere, hyperv)
  get mirror coverage for the first time in production, via a single
  wildcard entry instead of a per-host map.
- Flux's own install is no longer the one unmirrored exception — its
  chart source and controller image registry resolve through
  `registry_mirror` like everything else.
- Terraform provider installation reuses the same registry endpoint
  instead of requiring a second, protocol-specific mirror server —
  generic-artifact OCI storage covers it.
- Mirrored image references keep their original `@sha256:...` digest —
  a mirror serves the same content at a different host, so Kyverno's
  `require-image-digest` policy needs no change.
- Vendored content (CRDs, Grafana dashboards) and the blueprint's own
  Terraform/Kustomize source need no separate mirroring once the
  blueprint itself ships as an OCI artifact — they're already inside it.
- EKS/AKS node-level image pulls stay unmirrored by this ADR. Closing
  that gap means wiring the cloud's own pull-through cache (ECR cache
  rules, ACR cache rules) into the AWS/Azure cluster modules, a separate
  decision for whenever that platform work is prioritized.
- Windsor never writes to the mirror and doesn't prescribe how it gets
  populated. Its output is a generated SBOM; turning that into a
  populated registry is the operator's own process.

## Non-goals

- Standing up, operating, or populating the mirror. `registry_mirror.url`
  names infrastructure Windsor doesn't own; only the workstation-local
  fallback container is Windsor-managed, and only for dev.
- Prescribing a population mechanism. Pull-through caching, scheduled
  sync, and manual push are all valid; Windsor's output is a manifest,
  not a sync job.
- Git-sourced charts (fluentd). Git isn't OCI; mirroring it is a
  different problem this ADR doesn't take on.
- EKS/AKS node-level image pulls. No per-node hook exists to drive; the
  cloud's own registry mirror feature is the answer, left to future work.
- Implementing the CLI-side provider fetch (§5). That's `windsor` CLI
  work in the sibling `cli` repo; this ADR fixes the OCI addressing
  contract `core` needs to hold up its end.

## Alternatives considered

**Nest the setting under `cluster.mirror`, as `feature/mirror`
prototyped.** Undersells its scope — it also governs Terraform's Flux
bootstrap and Terraform provider installation, not just cluster config.
Top-level matches the convention already used for other cross-cutting
capabilities.

**Rewrite every chart's `image:`/digest reference in values at render
time instead of relying on containerd-level redirection.** Doubles the
maintenance surface — every chart's values schema differs — for
something Talos's native mirror already solves losslessly: same digest,
different host, no values diff.

**Leave Terraform providers on a separate, protocol-native mirror
(Terraform's own `network_mirror` HTTP protocol via `terraform providers
mirror`).** Works, but means an operator stands up and populates two
different mirror services instead of one. Storing provider packages as
generic OCI artifacts on the same registry this ADR already requires
keeps it to one endpoint, one manifest, one thing to populate.

**Recommend a specific self-hosted registry or population tool (e.g. a
pull-through cache) as part of this decision.** Out of scope by design —
the mirror is assumed to exist and be populated by the operator's own
means. Prescribing an implementation here would constrain environments
that already run a registry (Harbor, ECR, an internal Artifactory) for
reasons unrelated to this blueprint.

## References

- `feature/mirror` (`a4cecc38`, unmerged, stale) — prior art for the
  envsubst fallback pattern and Talos `overridePath` scheme this ADR
  builds on.
- `docs/adr/roadmap-v0.8.0.md` — where this was previously deferred as
  premature.
- `contexts/_template/facets/option-workstation.yaml`,
  `config-talos.yaml` — the existing per-host pull-through mechanism this
  ADR leaves in place as the workstation default.
- `terraform/gitops/flux/main.tf` — Flux's own hardcoded OCI bootstrap
  source, and the blueprint `GitRepository` this ADR expects to become
  an `OCIRepository` on the same registry.
- `kustomize/crds/sources.yaml`, `kustomize/observability/resources/grafana/dashboards/*/source.yaml` —
  the vendoring conventions (`task crds`, `task dashboards`) that make
  vendored content ride along in the blueprint artifact instead of
  needing separate mirroring.
- `kustomize/policy/resources/kyverno/require-image-digest/` — the
  digest-pinning policy this design doesn't disturb.
