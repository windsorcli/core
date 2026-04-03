---
name: kustomize-author
description: Author kustomize components, patches, and overlays using Windsor Core conventions. Knows base/resources/components layering, HelmRelease patterns, patch types, and timeout/interval rules.
---

# Kustomize Author

## Apply when
- Creating or editing any `kustomization.yaml`, `helm-release.yaml`, `helm-repository.yaml`, or patch file under `kustomize/`
- Adding a new kustomize component or overlay
- Reviewing kustomize structure for conformity

## Directory structure

```
kustomize/<domain>/
  base/                   # installs the operator/CRDs (HelmRelease + HelmRepository)
    kustomization.yaml    # kind: Kustomization — references base resources and components
    namespace.yaml        # Namespace resource (if domain-specific)
    <tool>/
      kustomization.yaml  # kind: Component — HelmRelease + HelmRepository
      helm-release.yaml
      helm-repository.yaml
  resources/              # configures/extends what base installed
    kustomization.yaml    # kind: Kustomization
    <feature>/
      kustomization.yaml  # kind: Component — patches or additional resources
      patches/
        helm-release.yaml
  namespace.yaml          # shared Namespace for the domain (when base/namespace.yaml absent)
```

**Key rule**: `base/` installs, `resources/` configures. Never put operator-level HelmReleases in `resources/`, and never put application config in `base/`.

## Kustomization kinds

### Kustomize Component (`kind: Component`)
Use for optional, composable units that facets reference via `components:`.

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - helm-release.yaml
  - helm-repository.yaml
```

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
patches:
  - path: patches/helm-release.yaml
```

Components **never** include other components — they are leaf nodes. No `components:` field inside a Component.

### Kustomize Kustomization (`kind: Kustomization`)
Use for the base or resources root that Flux reconciles.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
components: []
```

## HelmRelease pattern

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <tool-name>
  namespace: <domain-namespace>
spec:
  interval: 5m          # 10m for heavy/stable tools (Prometheus, Grafana)
  timeout: 10m          # see timeout formula below
  chart:
    spec:
      chart: <chart-name>
      version: "x.y.z"
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
        namespace: <domain-namespace>
  values: {}
```

## HelmRepository pattern

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <repo-name>
  namespace: <domain-namespace>
spec:
  interval: 10m         # always 10m for HelmRepositories
  url: https://charts.example.com
```

## Timeout and interval rules

From `kustomize/GUIDELINES.md`:

| Images in HelmRelease | Timeout |
|-----------------------|---------|
| 1–2 | 10m |
| 3–4 | 20m |
| 5+ | 30m |

| Component type | Interval |
|----------------|----------|
| Standard | 5m |
| Heavy/stable (Prometheus, Grafana, etc.) | 10m |
| HelmRepositories | 10m |

**Kustomization timeout** (set in facet YAML): `max(all HelmRelease timeouts)` within that kustomization.

## Patches

### Strategic merge patch (most common)
Patch a HelmRelease's values or spec:

```yaml
# patches/helm-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx-ingress
  namespace: ingress
spec:
  values:
    controller:
      service:
        type: NodePort
```

### JSON patch (for precise array/field ops)
```yaml
# patches/helm-release.json
[
  {
    "op": "replace",
    "path": "/spec/values/controller/replicaCount",
    "value": 2
  }
]
```

Use strategic merge patches by default. Use JSON patches only when strategic merge cannot target the field (e.g., array element replacement, removing a key).

## Component naming conventions

Component subdirectory names are kebab-case and describe the variation they enable:

- `loadbalancer/` — adds loadbalancer service type
- `nodeport/` — adds nodeport service type
- `coredns/` — adds CoreDNS integration
- `web/` — adds ingress/web exposure
- `prometheus/` — adds Prometheus monitoring
- `flux-webhook/` — adds Flux webhook receiver
- `dev/` — adds dev-mode settings
- `skip-tls/` — disables TLS verification (dev only)

A component named for its purpose, not its content ("loadbalancer" not "service-type-loadbalancer").

## Namespace references

Each domain has exactly one Namespace resource, referenced from `base/kustomization.yaml`. Components inherit the namespace from the Kustomization that selects them — do not redeclare namespaces in components.

## Flux variable substitution

When a facet sets `substitutions:`, use `${VAR_NAME}` syntax in kustomize resources:

```yaml
# In kustomization.yaml (base or resources root)
patches:
  - target:
      kind: HelmRelease
    patch: |
      - op: replace
        path: /spec/values/ingress/host
        value: webhook.${external_domain}
```

Variables are injected by Flux at reconcile time. Never hardcode domain values — reference substitution vars.

## Image pinning

When overriding image tags in HelmRelease values, always pin to `tag@sha256:<digest>` using the **multi-arch manifest list digest**, not a single-platform image digest.

### Workflow

1. Find the default image used by the chart:
   ```bash
   helm show values <repo>/<chart> --version <version>
   ```
   Look for `image.tag`, `image.digest`, or vendor-specific fields.

2. Get the cross-platform manifest list digest:
   ```bash
   # Preferred — returns manifest list digest if available
   crane digest --platform all <image>:<tag>

   # Alternative
   docker manifest inspect <image>:<tag> | jq -r '.digest // .manifests[0].digest'
   ```
   The result must be the digest of the **manifest list** (index), not a single-platform layer.
   Verify: `crane manifest <image>:<tag> | jq .mediaType` should be
   `application/vnd.oci.image.index.v1+json` or `application/vnd.docker.distribution.manifest.list.v2+json`.

3. Pin in HelmRelease values:
   ```yaml
   values:
     image:
       tag: "v1.2.3@sha256:<manifest-list-digest>"
   ```

### Rules

- Always use the manifest list digest (multi-arch), never a single-architecture image digest.
- Keep the human-readable tag prefix (`v1.2.3@sha256:...`) so the version is still visible in `helm list`.
- When bumping a chart version, re-derive the digest — do not reuse a digest from a prior chart version.
- Do not pin the digest if the chart already pins it internally and the override value is not needed.

## What NOT to do

- Do not put `kind: Kustomization` inside a component directory
- Do not nest components inside other components
- Do not reference cross-domain namespaces in helm-release resources
- Do not use `helmChartInflationGenerator` — always use `HelmRelease` + Flux
- Do not hardcode image tags in HelmRelease values when the chart default is appropriate
- Do not create a `resources/` directory that also contains a HelmRepository
- Do not use single-platform image digests when a manifest list digest is available
