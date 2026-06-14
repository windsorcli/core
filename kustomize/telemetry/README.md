---
title: Telemetry add-on
description: kube-prometheus-stack and FluentBit for cluster-level metrics and log collection.
---

# Telemetry

The cluster's metrics and log-collection layer. Prometheus scrapes
workloads, and FluentBit ships logs to whatever downstream the
observability add-on wires up. Two flags drive it,
`telemetry.metrics.enabled` and `telemetry.logs.enabled`,
independently.

The add-on splits across two Kustomization paths so Flux can install
the chart-level CRDs before the cluster-resource CRs that depend on
them. `telemetry-base` ships the Helm releases
(kube-prometheus-stack, fluent-operator, filebeat as the
Elasticsearch alternative). `telemetry-resources` ships
ServiceMonitors, PrometheusRules, and the ClusterFluentBitConfig /
ClusterInput / ClusterFilter / ClusterParser CRs, and depends on
`telemetry-base`.

Component-name collisions are worth flagging. `prometheus`,
`prometheus/flux`, and `fluentbit` exist as components in BOTH facets.
The same literal name points at the Helm release in `telemetry/base/`
and at the consuming CR set in `telemetry/resources/`. The descriptor
below disambiguates with `base/` and `resources/` prefixes. Operators
still write the bare names (`components: [prometheus]`) in their
facets, and the prefix resolves from the facet's `path:`.

The namespace runs at PSA `privileged` because some components
(FluentBit reading the host log path, metrics-server with host
networking) need it.

## Architecture

```mermaid
flowchart LR
  flux[Flux helm-controller]

  subgraph systemtelemetry[system-telemetry]
    prom_hr[HelmRelease kube-prometheus-stack]
    fb_hr[HelmRelease fluent-operator]
    ms_hr[HelmRelease metrics-server]

    prom[Prometheus + Alertmanager<br/>+ node-exporter + ksm]
    fb_ds[FluentBit DaemonSet]
    ms[metrics-server]

    sm[ServiceMonitors<br/>+ PrometheusRules]
    fb_crs[ClusterInput<br/>ClusterFilter<br/>ClusterParser]
  end

  hostlogs[(host log paths<br/>containerd + systemd)]
  observability[(observability add-on<br/>Grafana / log store)]

  flux ==> prom_hr & fb_hr & ms_hr
  prom_hr --> prom
  fb_hr --> fb_ds
  ms_hr --> ms
  sm -.scraped by.-> prom
  fb_crs -.config.-> fb_ds
  fb_ds -.reads.-> hostlogs
  fb_ds -.ships.-> observability
  prom -.metrics datasource.-> observability
```

The base half installs the Helm charts (Prometheus, FluentBit
operator, metrics-server). The resources half wires up scrape targets
and collector configuration. The observability add-on attaches
Grafana on top of Prometheus and routes FluentBit's output to a log
store.

## Recipes

### Metrics only

```yaml
- name: telemetry-base
  path: telemetry/base
  components: [prometheus, prometheus/flux]
  timeout: 30m

- name: telemetry-resources
  path: telemetry/resources
  dependsOn: [telemetry-base]
  components: [metrics-server, prometheus, prometheus/flux]
```

### Logs only

```yaml
- name: telemetry-base
  path: telemetry/base
  components: [fluentbit]

- name: telemetry-resources
  path: telemetry/resources
  dependsOn: [telemetry-base]
  components:
    - fluentbit
    - fluentbit/containerd
    - fluentbit/kubernetes
    - fluentbit/parser
    - fluentbit/systemd
```

### Metrics + logs (default when both flags are on)

```yaml
- name: telemetry-base
  path: telemetry/base
  components: [prometheus, prometheus/flux, fluentbit]

- name: telemetry-resources
  path: telemetry/resources
  dependsOn: [telemetry-base]
  components:
    - metrics-server
    - prometheus
    - prometheus/flux
    - fluentbit
    - fluentbit/containerd
    - fluentbit/kubernetes
    - fluentbit/parser
    - fluentbit/systemd
    - fluentbit/prometheus
```

### Elasticsearch-mode (filebeat replaces FluentBit)

When `addons.observability.logs_driver == 'elasticsearch'`, the
addon-observability facet declares `strategy: replace` to swap
FluentBit for Filebeat at the telemetry-base layer. The base
`prometheus` and `prometheus/flux` components stay. `fluentbit` is
removed and `filebeat` is added.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Components — `telemetry-base`

| Component | Enable when | Effect |
|---|---|---|
| `base/prometheus` | `telemetry.metrics.enabled: true` | Helm release of `kube-prometheus-stack` (chart) in `system-telemetry`. Provides Prometheus, Alertmanager, node-exporter, kube-state-metrics. Grafana sub-chart is disabled (Grafana lives in the observability add-on). Chart CRD install is skipped; the prometheus-operator CRDs are vendored under `kustomize/crds/` and applied ahead of the controller via the facet `crds:` section. |
| `base/prometheus/flux` | `telemetry.metrics.enabled: true` | Patches the kube-prometheus-stack HelmRelease to scrape Flux controller metrics and enable the bundled Flux dashboards. |
| `base/fluentbit` | `telemetry.logs.enabled: true` | Helm release of the `fluent-operator` chart in `system-telemetry`. Installs the FluentBit operator CRDs and a FluentBit DaemonSet on every node. The actual collector configuration ships as the `resources/fluentbit/*` components. |
| `base/filebeat` | `addons.observability.logs_driver == 'elasticsearch'` (telemetry-base is replaced) | Helm release of Elastic's Filebeat chart, used instead of FluentBit when Elasticsearch is the log driver. Wired by the `addon-observability` facet's `strategy: replace` override of telemetry-base. |

## Components — `telemetry-resources`

| Component | Enable when | Effect |
|---|---|---|
| `resources/metrics-server` | `telemetry.metrics.enabled: true` AND `telemetry.metrics_server_enabled: true` | Helm release of `metrics-server` for `kubectl top` and HPA. Some platforms (EKS / AKS) ship a managed metrics-server; gate this off when one is already present. |
| `resources/metrics-server/skip-tls` | default (when metrics-server is enabled in a cluster with selfsigned kubelet certs) | Patches the metrics-server Deployment to add `--kubelet-insecure-tls`. Required on Talos and other distros where kubelet serves cert-manager-issued or selfsigned certs. |
| `resources/prometheus` | `telemetry.metrics.enabled: true` | ServiceMonitors and PrometheusRules that target the blueprint's core workloads (kube-state-metrics, the API server, etcd via Talos discovery). The ServiceMonitor / PrometheusRule CRDs come from the vendored `crds:` layer, applied ahead of the whole stack. |
| `resources/prometheus/flux` | `telemetry.metrics.enabled: true` | ServiceMonitor for Flux controllers and a PrometheusRule with the upstream Flux alert set. |
| `resources/fluentbit` | `telemetry.logs.enabled: true` | `ClusterFluentBitConfig` + `ClusterOutput` (no-op by default; outputs are added by `addon-observability` based on `logs_driver`). Establishes the base FluentBit pipeline. |
| `resources/fluentbit/containerd` | `telemetry.logs.enabled: true` | `ClusterInput` reading containerd logs from `/var/log/containers/*.log` with the multiline-parser configuration for containerd's CRI log format. |
| `resources/fluentbit/kubernetes` | `telemetry.logs.enabled: true` | `ClusterFilter` enriching log records with Kubernetes metadata (Pod / Namespace / Container labels) from the kubelet API. |
| `resources/fluentbit/parser` | `telemetry.logs.enabled: true` | Base parser definitions (JSON, logfmt) plus optional sub-overlays for `service-name`, `logfmt`, `grpc` that opt-in additional structured-log shapes. |
| `resources/fluentbit/systemd` | `telemetry.logs.enabled: true` | `ClusterInput` reading systemd journal entries. Captures node-level events that don't reach the containerd log path. |
| `resources/fluentbit/prometheus` | `telemetry.logs.enabled: true` AND `telemetry.metrics.enabled: true` | ServiceMonitor for FluentBit's metrics endpoint. |
| `resources/fluentbit/fluentd` | `telemetry.logs.driver == 'fluentd'` | `ClusterOutput` shipping records to the central FluentD aggregator in `system-observability`. Activates when the observability add-on is in fluentd mode. |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|

<!-- END_KUSTOMIZE_DOCS -->

## See also

- [contexts/_template/facets/platform-base.yaml](../../contexts/_template/facets/platform-base.yaml) for the canonical wiring for both facets.
- [contexts/_template/facets/addon-observability.yaml](../../contexts/_template/facets/addon-observability.yaml) for the Elasticsearch override (replaces telemetry-base with filebeat).
- Related add-ons: [observability](../observability/) (Grafana / log store downstream of telemetry), [policy](../policy/) (admission policies apply to system-telemetry pods).
