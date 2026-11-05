---
title: "ADR-0020: Helm charts from a single chart registry"
description: "charts.registry makes a cluster pull every chart core installs from one OCI registry instead of each vendor. OCI-published charts use OCIRepository with a substituted base URL. HTTP-published charts keep their HelmRepository and carry a sibling chart-registry component that swaps it for an OCIRepository when a chart registry is set."
---

# ADR-0020: Helm charts from a single chart registry

## Status

Proposed. Replaces the approaches in
[core#3236](https://github.com/windsorcli/core/pull/3236) (one shared OCI
HelmRepository) and [core#3235](https://github.com/windsorcli/core/pull/3235)
(URL prefix on OCI HelmRepositories), and
[core#1584](https://github.com/windsorcli/core/pull/1584) (docker and helm
mirrors). Builds on the `chart_repository`
Terraform inputs from [core#3221](https://github.com/windsorcli/core/pull/3221).

## Context

By default a cluster pulls every Helm chart straight from its vendor. Some
sites need every chart to come from one registry they control instead:
air-gapped clusters, sites that review each artifact before it enters the
cluster, and sites that hit upstream rate limits. The site copies a fixed set
of charts into that registry, and the cluster pulls from it from its first
install. The registry is OCI in every case worth designing for: Harbor, Zot,
Artifactory, Nexus, ECR, ACR, GAR, and GHCR all store Helm charts as OCI
artifacts.

### A chart registry is not a mirror

A mirror is a transparent copy of one upstream, at the same paths. Clients
keep asking for `ghcr.io/...` and the runtime serves it from somewhere else. A
chart registry differs in three ways: there is no single upstream to copy, its
layout does not follow any upstream's paths, and Flux source-controller does
not go through containerd mirrors, so the source objects themselves have to
name the registry.

Three related needs exist, and each uses a different mechanism with a
different kind of setting:

| Need | Mechanism | Setting | What changes |
|---|---|---|---|
| Pull-through cache for images | Per-host mirror in the container runtime | `docker.registries` (exists) | Nothing in the manifests |
| Charts from one registry the site controls | Chart registry (this ADR) | One registry location | Flux source objects |
| Another vendor's charts or images, such as Chainguard's | Replacement per chart, from an overlay blueprint | None in core | Source objects and values of the replaced charts |

This ADR covers the second row, and section 10 states what core keeps so the
third row stays possible. A replacement is a different artifact, not the same
one in a different place. Chainguard's first-party charts live at
`oci://cgr.dev/<org>/charts/<chart>`, are forks of Bitnami's charts with their
own values, and use tags such as `10.5.13-r1` that move as their images update.
Neither a mirror nor a registry prefix can express that, and core's
HelmRelease values do not apply to a forked chart.

### Digests and signatures

An OCI chart copied byte for byte keeps its upstream digest, so a digest pin
and the vendor's signature hold whether the chart comes from the vendor or
from the chart registry. An HTTP chart has neither: a HelmRepository chart
cannot be pinned by digest, and its OCI copy in the chart registry is a new
artifact with no vendor signature.

Of the OCI charts core pinned on 2026-10-28, six carry a cosign signature at
the pinned digest:

| Signature | Charts |
|---|---|
| Keyless sigstore bundle as an OCI referrer | cilium, fluent-operator, flux-operator, cloudnative-pg, coredns |
| Legacy `.sig` tag | cert-manager |
| None found | flux-instance, gateway-helm, grafana, kube-prometheus-stack, kyverno, metallb, openebs, trust-manager |

### How charts reach the cluster

Core installs charts through four different sources:

| Source | Objects | Examples |
|---|---|---|
| OCI-published charts | 13 | cilium, coredns, kyverno, cert-manager, grafana |
| HTTP-published charts | 17 HelmRepositories and 17 releases, from 11 upstream hosts | longhorn, external-dns, metrics-server, crossplane, elastic, hcloud, minio |
| `GitRepository` | 1 | fluentd (fluent-operator chart from git) |
| Terraform `helm_release` | 3 | flux-operator, flux-instance, cilium bootstrap |

Each chart's renovate annotation records its full upstream identity, for
example `datasource=docker depName=ghcr.io/kyverno/charts/kyverno` or
`datasource=helm package=longhorn helmRepo=https://charts.longhorn.io`.

### What Flux offers

- The `oci` type of HelmRepository is in maintenance mode, and the Flux docs
  direct OCI charts to `OCIRepository`. An OCI HelmRepository carries no
  status, so a Kustomization health check passes even when the registry is
  unreachable.
- `OCIRepository` reports a `Ready` condition, retries with backoff, pins by
  tag, semver, or digest, verifies cosign or notation signatures, and
  authenticates through `secretRef` (same namespace) or `provider: aws | azure
  | gcp` workload identity.
- A HelmRelease consumes an `OCIRepository` through `spec.chartRef`.
  `spec.chart` and `spec.chartRef` are mutually exclusive. Switching an
  existing release from `spec.chart` to `spec.chartRef` performs a Helm
  upgrade and garbage-collects the old HelmChart.
- `HelmChart` can only be built from a HelmRepository, GitRepository, or
  Bucket, never from an OCIRepository.

### HTTP charts need a different source kind

An OCI-published chart moves to the chart registry by changing a URL. An
HTTP-published chart does not: in the chart registry it exists only as an OCI
artifact, so the Flux object that fetches it has to be an OCIRepository
instead of a HelmRepository, and the HelmRelease has to use `spec.chartRef`
instead of `spec.chart`. Flux postBuild substitution and Kustomize patches
both operate on an object's fields and cannot change its kind. Swapping kinds
therefore means building a different set of objects when a chart registry is
set.

## Decision

### 1. One setting: `charts.registry`

`values.yaml` gains a top-level `charts` object with one field, `registry`:
an OCI registry host with an optional `oci://` scheme, port, and path.

```yaml
charts:
  registry: registry.example.com/windsor
```

When `charts.registry` is unset or empty, every chart comes from its vendor.
The key sits at the top level because the Terraform bootstrap reads it as
well as Flux, and cilium installs before Flux exists. It is an object so
credential settings have a place to go (section 8). The schema rejects any
other scheme.

`charts.registry` belongs to core's schema. The Windsor CLI MUST NOT read it.
A site gives the same registry to `windsor show artifacts --charts-to`
([cli ADR 0010](https://github.com/windsorcli/cli/blob/main/docs/adrs/0010-artifact-inventory-and-relocation.md)),
and the CLI writes each chart destination from that flag.

The `platform-base` facet normalizes the value once, into a computed
`chart_registry`: `oci://<host>/<path>` with no trailing slash, or empty when
`charts.registry` is unset. Every facet gate, the global `chart_registry`
substitution, and the Terraform inputs read that one value, so
`registry.example.com/windsor`, `oci://registry.example.com/windsor`, and
`registry.example.com/windsor/` behave the same.

### 2. Layout follows `helm push`

Helm has no mirror command. Its documented way to move a chart into an OCI
registry is `helm pull` followed by `helm push <chart>.tgz oci://<registry>`,
and `helm push` derives the reference from the chart itself: the basename is
the chart's `Chart.yaml` name and the tag is its `Chart.yaml` version, as a
strict requirement. Flux Mirror publishes an HTTP chart at the same
`<destination>/<chart name>:<version>` reference. Core adopts that contract
unchanged, so any tool that pushes charts the way Helm does produces the
layout core expects.

A chart MUST live in the chart registry at
`<charts.registry>/<chart name>:<chart version>`, with no extra path
segments, where the name and version are the ones in the chart's
`Chart.yaml`.

| Upstream | Reference for `registry.example.com/windsor` |
|---|---|
| `oci://ghcr.io/kyverno/charts/kyverno:3.9.2` | `registry.example.com/windsor/kyverno:3.9.2` |
| `https://charts.longhorn.io`, `longhorn` 1.13.0 | `registry.example.com/windsor/longhorn:1.13.0` |
| `https://operator.min.io`, `operator` 7.1.1 | `registry.example.com/windsor/operator:7.1.1` |

Every version core pins MUST be the chart's `Chart.yaml` version. An upstream
whose OCI tags differ from its chart versions is consumed from its HTTP
repository instead. No chart core installs needs this today. An example is
ingress-nginx: `registry.k8s.io` tags its chart `v4.15.1` while `Chart.yaml`
says `4.15.1`, so it would come from
`https://kubernetes.github.io/ingress-nginx`.

Chart names MUST be unique across everything core installs, and
`task charts:check` enforces it. Generic names such as minio's `operator`
cannot be qualified, because `helm push` offers no way to rename the
reference. A site that shares the registry with other blueprints gives core
its own path in `charts.registry`.

### 3. OCI-published charts use OCIRepository

Each OCI-published chart has an OCIRepository named after its HelmRelease,
and the release references it with `spec.chartRef`. This applies with or
without a chart registry, because it moves core off the maintenance-mode
HelmRepository type and gives every OCI chart a real health check.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: kyverno
  namespace: system-policy
spec:
  interval: 10m
  url: ${chart_registry:=oci://ghcr.io/kyverno/charts}/kyverno
  ref:
    # renovate: datasource=docker depName=ghcr.io/kyverno/charts/kyverno package=ghcr.io/kyverno/charts/kyverno
    tag: 3.9.2
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
```

When the `chart_registry` substitution is empty, the `:=` default supplies the
vendor's registry and path. `flux envsubst` treats an empty value the same as
an unset one here.

Every OCI chart source MUST write its URL as `${chart_registry:=<vendor URL>}`.
The Windsor CLI renders a context with an empty `chart_registry` to list each
chart's upstream, so a source with no vendor default has no upstream in that
list.

### 4. HTTP-published charts carry a sibling chart-registry component

The base of each HTTP chart keeps its HelmRepository and its `spec.chart`
reference, so a cluster without a chart registry pulls from the vendor's HTTP
repository. Next to the base, each HTTP chart ships a `chart-registry` Kustomize
Component that performs the swap:

```text
kustomize/csi/install/longhorn/
├── helm-release.yaml
├── helm-repository.yaml
├── kustomization.yaml
└── chart-registry/
    ├── kustomization.yaml
    └── oci-repository.yaml
```

```yaml
# chart-registry/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - oci-repository.yaml
patches:
  - patch: |-
      $patch: delete
      apiVersion: source.toolkit.fluxcd.io/v1
      kind: HelmRepository
      metadata:
        name: longhorn
        namespace: system-csi
  - patch: |-
      apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      metadata:
        name: longhorn
        namespace: system-csi
      spec:
        chart: null
        chartRef:
          kind: OCIRepository
          name: longhorn
```

```yaml
# chart-registry/oci-repository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: longhorn
  namespace: system-csi
spec:
  interval: 10m
  timeout: 3m
  url: ${chart_registry}/longhorn
  ref:
    # renovate: datasource=helm depName=longhorn package=longhorn helmRepo=https://charts.longhorn.io
    tag: 1.13.0
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
```

Each HTTP chart's HelmRelease MUST use its own HelmRepository, named after the
release and defined next to it, even when two releases come from the same
vendor repository. Every chart-registry component then deletes exactly the
HelmRepository beside it, with no component that only deletes a source shared
with another release. A second HelmRepository for the same URL costs one more
index fetch per interval. `task charts:check` builds each chart-registry component
on top of its base, so a patch whose target is missing, such as a HelmRelease
still on `helm.toolkit.fluxcd.io/v2beta1`, fails CI.

Every facet entry that installs an HTTP chart MUST list its chart-registry component
behind the computed value, using the conditional-component pattern facets
already use:

```yaml
components:
  - longhorn
  - "${chart_registry != '' ? 'longhorn/chart-registry' : ''}"
```

The chart-registry component MUST be listed after the base component and after any
overlay that patches the HelmRelease's `spec.chart`. No overlay does today.

### 5. One version per chart

An HTTP chart's version appears twice: in the base HelmRelease's
`spec.chart.spec.version` and in the registry OCIRepository's `spec.ref.tag`.
Both copies MUST carry the same renovate annotation, so one renovate PR bumps
both. `task charts:check` MUST fail when they differ, in the same way
`task crds:check` guards vendored CRDs. An OCI chart's version appears once, in
its OCIRepository.

### 6. Terraform-installed charts read the same registry

The `gitops/flux` and `cni/cilium` stacks already take a `chart_repository`
input. When `chart_registry` is set, the facets MUST pass it as that input.
Helm appends the chart name, so flux-operator, flux-instance, and cilium land
at the same layout. When it is empty, the facets pass `null` and the stacks
keep their defaults. The stacks themselves do not change, and
`task charts:check` reads their chart versions from the stacks' variable
defaults.

The `chart_repository` default in each stack MUST stay the vendor URL. The
Windsor CLI evaluates Terraform variables from their defaults, and reads the
upstream of flux-operator, flux-instance, and cilium from that value.

### 7. The site fills the registry with Flux Mirror

Core does not publish or republish charts, and it keeps no list of them. The
site copies them into its registry with
[Flux Mirror](https://fluxcd.io/flux/cli-plugins/flux-mirror/), the Flux CLI
plugin for registry relocation. `windsor show artifacts` writes the Flux Mirror
config for one context from its composed blueprint:

```sh
flux plugin install mirror
windsor show artifacts --charts-to registry.example.com/windsor -o flux-mirror | flux mirror sync -
```

The config lists every chart the context installs, at its pinned version.
`charts` entries publish HTTP charts as OCI at `<destination>/<chart name>:<version>`.
`artifacts` entries copy OCI charts byte for byte, so they keep their upstream
digests. Registry credentials come from the Docker config, or from the
config's `hosts` section for workload identity on ECR, ACR, and GAR.

Flux Mirror re-runs skip tags already present and report upstream drift.
The plugin is in preview, so its config API MAY change between releases.

### 8. Credentials come from cloud identity or a site-provided secret

OCIRepositories that pull from the chart registry set `provider` from the
registry host: `aws` for `*.dkr.ecr.*.amazonaws.com`, `azure` for
`*.azurecr.io`, `gcp` for `*-docker.pkg.dev`, and `generic` otherwise. ECR,
ACR, and GAR registries then authenticate through workload identity with no
secret. For a registry that needs static credentials, the site creates a pull
secret with a fixed name in each chart namespace, and those OCIRepositories
reference it through `secretRef`. Core does not create or copy the secret.
`flux mirror secret` can write it from the same `hosts` credentials the sync
uses.

A workstation context can host the chart registry for local tests. When
`charts.registry` names `<name>.<dns domain>`, the `workstation` facet adds a
local registry called `<name>` and sets the `chart_registry_insecure`
substitution, so every OCIRepository pulls over plain HTTP. Helm falls back to
plain HTTP by itself, so the Terraform-installed charts need no setting. Every
other context keeps TLS.

### 9. OCI charts pin a digest and verify the vendor's signature

Each OCIRepository MUST set `ref.digest` next to `ref.tag`, so the cluster
pulls the same chart from the vendor and from the chart registry. The renovate
annotation MUST cover both fields, so one PR bumps the tag and its digest
together. Where the vendor signs the chart (see Context), the OCIRepository
MUST set `verify` with `provider: cosign` and the vendor's OIDC issuer and
subject. Charts with no signature stay unverified rather than verified against
an identity core invents.

HTTP charts get neither. Their HelmRepository cannot pin a digest, and their
registry copy carries no vendor signature.

### 10. Core keeps every chart replaceable

Core does not offer a vendor switch such as Chainguard in its schema. A site
or vendor replaces charts through an overlay blueprint, and core keeps these
properties so that works without forking core:

- Each chart MUST have exactly one source object, named after its
  HelmRelease, in the release's namespace (sections 3 and 4).
- Every chart source MUST be an object that the Windsor CLI reads when it
  renders a context: an OCIRepository, a HelmRepository that a HelmRelease
  names in `spec.chart`, or a Terraform `helm_release`.

An overlay replaces a chart with inline patches on core's Kustomization of
the same name. The Windsor CLI appends patches from every facet that names a
Kustomization. A replacement for grafana patches the `grafana` OCIRepository's
URL, digest, `secretRef`, and `verify`, and replaces the HelmRelease values.
An overlay cannot add a component from its own source to a core
Kustomization, because a Kustomization resolves every component against its
one source.

## Consequences

Setting `charts.registry` changes source URLs and swaps 17 HTTP
HelmRepositories for OCIRepositories. HelmRelease values, overlays, and
namespaces stay as they are, and no release refers to a source outside its
own namespace.

A missing chart or wrong registry fails at the OCIRepository's `Ready`
condition, inside the tier that installs the chart. It does not surface later
as an unexplained HelmChart failure.

The 13 OCI charts change from `spec.chart` to `spec.chartRef` once, on every
existing cluster. Flux handles the switch with a Helm upgrade to the same
chart version, which the upgrade integration test covers.

Each HTTP chart gains a `chart-registry/` directory with two files, and each facet
entry that installs one gains a conditional component line. A chart added
later without a chart-registry component would keep pulling from its vendor, so
`task charts:check` MUST also fail when an HTTP chart's HelmRelease has no
sibling `chart-registry/` component.

`OCIRepository.spec.secretRef` only resolves in its own namespace, so a
registry with static credentials needs a pull secret in each chart namespace.
Cloud registries avoid this through `provider`.

## Alternatives considered

### One shared OCI HelmRepository (core#3236)

A `helm-mirror` HelmRepository in `system-gitops`, every `sourceRef` rewritten
to it, and every upstream HelmRepository hidden with `ssa: Ignore`. Rejected:
it depends on the maintenance-mode `oci` type, which has no health status; it
leaves upstream HelmRepositories orphaned on a running cluster; and it needs
substitutions in every HelmRelease and HelmRepository.

### URL prefix on OCI HelmRepositories (core#3235)

Rejected as a complete answer because it covers only charts that are already
OCI, leaving the 17 HTTP charts on the internet. Its substitution approach
survives in section 3, applied to OCIRepository instead of HelmRepository.

### Keep the upstream path or a vendor prefix in the chart registry

Charts would live at `<registry>/<upstream host>/<upstream path>/<chart>`, or
at `<registry>/<vendor>/<chart>` for generic names, which avoids collisions
with charts from other blueprints. Rejected: `helm push` cannot produce either
layout without a per-chart push target, HTTP upstreams have no OCI path to
keep, and a dedicated `charts.registry` path gives a site the same isolation.

### One key for charts and images

A single `registry` or `mirror` key would cover charts now and images later.
Rejected: the image needs in the context table use a per-host mirror map and
a per-image replacement map. Neither fits a single prefix, so one key would
end up meaning different things for different artifacts.

### Flip HelmRepository `type` to `oci` by substitution

HTTP HelmRepositories would become `type: oci` with the chart registry's URL,
keeping `spec.chart` everywhere. Rejected because it moves every chart onto
the maintenance-mode type when a chart registry is set.

### Core republishes HTTP charts as OCI

Core would push the HTTP-only charts to its own registry so every chart has
an OCI upstream. Rejected: core would become a chart distributor, with a
registry to operate and an artifact push on every chart bump.

### Mutate sources at admission with Kyverno

A Kyverno policy would rewrite source URLs as they are applied, as Zarf's
agent does. Rejected: admission mutation cannot change an object's kind, so
it cannot turn a HelmRepository into an OCIRepository. Kyverno is itself one
of the charts the policy would have to rewrite, so the policy cannot exist
before it is needed.

### Registry that serves Helm HTTP repositories

Artifactory and Nexus can proxy each HTTP upstream as an HTTP Helm repository,
so the HTTP HelmRepositories would only need a URL change. Rejected as the
primary design: OCI-only registries cannot do it, and each upstream maps to an
arbitrarily named remote repository rather than one location, so the setting
would become a per-upstream map. Core MAY add this later as a second option.

### Flux Operator ResourceSet per chart

A ResourceSet would render either a HelmRepository or an OCIRepository from
one set of inputs, with the version stated once and inventory-based garbage
collection on a swap. Rejected for now: the rendering happens in the cluster,
out of reach of `kustomize build` and the facet tests; the HelmRelease still
needs its `chartRef` kind flipped by substitution; and every chart source
would depend on flux-operator templating with `<< >>` syntax.

### ArtifactGenerator and ExternalArtifact

An ArtifactGenerator (`source.extensions.fluxcd.io/v1beta1`, from
source-watcher) would wrap either source in an ExternalArtifact, so every
HelmRelease could use `chartRef: {kind: ExternalArtifact}` in both modes.
Rejected for now: it adds two objects per chart and a controller core does not
run, needs helm-controller's `ExternalArtifact` feature gate, and is a beta
API. The HelmRepository/OCIRepository swap still happens, one level down.

### A core push script

A script in core would `helm pull` each chart and `helm push` it to the
registry. Rejected: it only knows core's file layout, so every other blueprint
would need its own, and `helm push` writes a new manifest, which changes an
OCI chart's digest. Flux Mirror does the copy from a declarative list and keeps
digests.

### Hauler or Zarf

Both bundle charts and images into an archive that can be carried into an
air gap. Rejected as the core tool: Hauler's documented registry layout adds a
`hauler/` path segment that breaks section 2, and Zarf brings its own deploy
model and in-cluster registry alongside Windsor's. A site MAY still use either
to move artifacts into a registry that follows section 2.

### A vendor switch in core's schema

A setting such as `charts.vendor: chainguard` would make core swap its charts
and images for one vendor's builds. Rejected: entitlements, paths, tags, and
values differ per vendor and per customer, so core would carry and test a
second set of releases for each vendor. An overlay blueprint carries that set
instead (section 10).

### Blueprint-wide patch in the Windsor CLI

The CLI would apply one patch to every Kustomization it generates, matching
`kind: HelmRepository`. Rejected: patches cannot change kind either, and the
CLI only supports patches per Kustomization today.

## Implementation slices

1. Add `charts.registry` to the schema and the computed `chart_registry` to
   `platform-base`, with facet tests for unset, set, normalized, and rejected
   values.
2. Convert the 13 OCI-published charts to OCIRepository and their releases to
   `chartRef`. Verify with the fresh and upgrade integration runs.
3. Add `chart-registry/` components for the HTTP-published charts and wire them into
   the facets.
4. Add `task charts:check` and run it in CI.
5. Pass `chart_registry` to the Terraform `chart_repository` inputs.
6. Add `provider` and `secretRef` to the OCIRepositories (section 8).
7. Decide the fluentd GitRepository source (see open questions).
8. Add `ref.digest` to the OCIRepositories with a renovate manager for the
   tag and digest pair, and `verify` to the six signed charts (section 9).

## Open questions

- `secretRef` has to be absent when the registry allows anonymous pulls, but
  the 13 OCI-published charts have no chart-registry component to add it from. The
  `charts` field that signals a site-provided secret, and the mechanism that
  sets `secretRef` on those OCIRepositories only when it is present, are not
  decided.
- The fluentd release builds its chart from a GitRepository. It either moves
  to the published fluent-operator OCI chart already used by fluentbit, or
  gains a chart-registry component of its own.
- Unsetting `charts.registry` reverses `spec.chartRef` to `spec.chart` for the
  HTTP charts. The Flux docs describe only the forward switch, so the reverse
  needs an integration run.
- Two parts of section 9 are untested. Flux Mirror's `includeReferrers` may
  not copy ghcr's `sha256-<digest>` referrer tags or cert-manager's `.sig`
  tag, and Flux's `verify` has to accept the sigstore v0.3 bundle format
  these charts use. Both need a run against a local registry before the
  `verify` blocks ship.
- HTTP charts have no digest pin or vendor signature (section 9). A site
  could sign its copies during the sync and the cluster could verify them
  against the site's identity, which needs a `charts` setting for that
  identity. The alternative is to prefer a vendor's OCI chart whenever its
  tags equal its `Chart.yaml` versions.
- A full air gap also needs container images, Terraform providers, and the
  Talos node image, which this decision does not cover. The Windsor CLI finds
  images in rendered manifests and through built-in extractors, and core
  declares no image list. No manifest or extractor names the Talos node
  image, so a site copies it without the CLI's list.

## References

- [Flux HelmRepository: Type](https://fluxcd.io/flux/components/source/helmrepositories/#type)
- [Flux OCIRepository](https://fluxcd.io/flux/components/source/ocirepositories/)
- [Flux HelmRelease: Chart reference](https://fluxcd.io/flux/components/helm/helmreleases/#chart-reference)
- [Flux ArtifactGenerator](https://fluxcd.io/flux/components/source/artifactgenerators/)
- [Flux Operator ResourceSet](https://fluxoperator.dev/docs/crd/resourceset/)
- [Flux Mirror config](https://fluxcd.io/flux/cli-plugins/flux-mirror/config/)
- [How to use Chainguard Helm charts](https://edu.chainguard.dev/chainguard/containers/how-to-use/use-chainguard-helm-charts/)
