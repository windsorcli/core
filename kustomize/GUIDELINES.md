# Kustomize Timeout and Interval Guidelines

## Quick Reference

### Timeout Formula

```
timeout = (number_of_images × 4-5min) + 50% buffer
```

| Images | Timeout |
|--------|---------|
| 1 | 10m |
| 2 | 10m |
| 3-4 | 20m |
| 5+ | 30m |

### Interval Guidelines

| Component Type | Interval |
|---------------|----------|
| Critical path (blocks others) | 5m |
| Standard | 5m |
| Heavy/stable (Prometheus, Grafana, etc.) | 10m |
| HelmRepositories | 10m |

## HelmRelease Configuration

### Counting Images

Count all container images explicitly configured in the HelmRelease `values` section:
- Main application image
- Sidecar images
- Init container images
- Operator images (if separate from main)

**Example:**
```yaml
values:
  image:
    tag: v1.0.0          # 1 image
  sidecar:
    image:
      tag: v2.0.0        # +1 image = 2 total → 10m timeout
```

### Setting Timeout and Interval

Configure in `kustomize/*/helm-release.yaml`:

```yaml
spec:
  interval: 5m          # Standard: 5m, Heavy: 10m
  timeout: 10m          # Based on image count (see table above)
```

## Chart Sources

Every chart source sets `interval: 10m`, and every chart MUST be pullable from `charts.registry`. `task charts:check` enforces the rules below in CI.

A chart published as OCI uses an `oci-repository.yaml` holding one OCIRepository per chart, named after its HelmRelease. The URL defaults to the vendor and switches to `charts.registry` through the `chart_registry` substitution. The HelmRelease references it with `chartRef`:

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
  insecure: ${chart_registry_insecure:=false}
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
```

A chart published only over HTTP keeps a `helm-repository.yaml` HelmRepository, named after its HelmRelease and used by no other release, and `spec.chart` in its HelmRelease. Next to it, a `chart-registry/` component replaces the HelmRepository with an OCIRepository at `${chart_registry}/<chart name>` and switches the HelmRelease to `chartRef`. Its `ref.tag` MUST match the HelmRelease's `spec.chart.spec.version`, under the same renovate annotation. Facets add the component after the base component when `chart_registry != ''`.

A chart lives in `charts.registry` at `<chart name>:<chart version>`, the reference `helm push` writes, so every pinned version MUST be the chart's `Chart.yaml` version. An HTTP chart's `chart-registry/` OCIRepository MAY put the chart under a path prefix, `${chart_registry}/<prefix>/<chart>`, when the chart name is generic. To fill a registry for one context, run `windsor show artifacts --charts-to <registry> -o flux-mirror | flux mirror sync -`. Every OCIRepository MUST set `insecure: ${chart_registry_insecure:=false}`, which is true only when the chart registry is a workstation registry.

To test the chart registry on a Colima workstation context, set `charts.registry` to `<name>.<dns domain>:5000/windsor`. The workstation then runs a local registry called `<name>` and the chart sources pull from it over plain HTTP. Run `windsor up` once without `charts.registry`. Then set `charts.registry` and run `windsor apply terraform workstation` to create the registry. Copy the charts into it with `windsor show artifacts --charts-to <name>.<dns domain>:5000/windsor -o flux-mirror | flux mirror sync -`, and run `windsor up` again.

## Kustomization Configuration

Set in `contexts/_template/features/*.yaml`:

**Kustomization timeout = max(contained HelmRelease timeouts)**

```yaml
kustomize:
- name: policy-base
  timeout: 30m          # Max of contained HelmReleases
  interval: 5m            # Standard: 5m, Heavy: 10m
```
