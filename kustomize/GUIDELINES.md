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

## HelmRepository Configuration

Set `interval: 10m` in all `kustomize/*/helm-repository.yaml` files:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
spec:
  interval: 10m
```

## Kustomization Configuration

Set in `contexts/_template/features/*.yaml`:

**Kustomization timeout = max(contained HelmRelease timeouts)**

```yaml
kustomize:
- name: policy-base
  timeout: 30m          # Max of contained HelmReleases
  interval: 5m            # Standard: 5m, Heavy: 10m
```
