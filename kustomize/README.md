---
title: Kustomize layer
description: Index of the cluster add-ons that ship with the Windsor Core blueprint.
---

# Kustomize

The Kustomize layer of the Windsor Core blueprint. Each subdirectory is an
add-on — a logically-grouped set of `HelmRelease`, `Certificate`, custom
resources, and patches that Flux reconciles after the cluster is up.

Add-ons are not applied directly. Facets in
[contexts/_template/facets/](../contexts/_template/facets/) emit Flux
`Kustomization` entries that reference these directories (`path:`) and
select per-cluster components. Multiple facets can contribute to the same
Kustomization name; the Windsor harness composes them into a single
materialized entry.

## Layout convention

Most add-ons follow a consistent shape:

```
kustomize/<add-on>/
├── namespace.yaml          # Namespace + PSA labels
├── kustomization.yaml      # Add-on root (often just resources: [namespace.yaml])
├── <operator>/
│   ├── kustomization.yaml  # kind: Component
│   ├── helm-repository.yaml
│   ├── helm-release.yaml
│   └── <variant>/          # Patches selected per-cluster
│       ├── kustomization.yaml  # kind: Component, patches: ...
│       └── patches/
└── README.md               # This add-on's reference (per-add-on READMEs)
```

Some add-ons split into `base/` (operators) and `resources/` (cluster
state) — pki, lb, gateway, telemetry, object-store. Others have a single
top-level kustomization — cni, csi, dns, policy, observability, gitops,
ingress, demo.

See [GUIDELINES.md](GUIDELINES.md) for the timeout / interval rules each
add-on's facet entries follow, derived from image count and reconcile
weight.

## Add-ons

### Bootstrap and platform

| Add-on | Owns | Wired by |
|---|---|---|
| [cni](cni/) | Cilium CNI (replaces kube-proxy, optional Gateway API + LBIPAM + Hubble). Bootstrapped by Terraform, adopted by Flux. | `option-cni` |
| [policy](policy/) | Kyverno admission controller and cluster-wide ClusterPolicies (image-digest enforcement, resource limits/requests audit). | `platform-base` |
| [pki](pki/) | cert-manager and trust-manager. Private and public ClusterIssuers — selfsigned, CA-backed, ACME (Let's Encrypt + Route53 / Azure DNS). | `platform-base`, `platform-aws`, `platform-azure`, `addon-private-ca`, `option-dev` |
| [telemetry](telemetry/) | Prometheus (kube-prometheus-stack), fluent-operator + fluent-bit, metrics-server. The collection layer; sinks live in `observability`. | `platform-base` |
| [gitops](gitops/) | Flux notification webhook receiver and HTTPRoute. Flux itself is installed by Terraform. | `platform-base` |

### Networking and traffic

| Add-on | Owns | Wired by |
|---|---|---|
| [gateway](gateway/) | Gateway API entrypoint — Envoy Gateway controller or Cilium's built-in Gateway. The shared `external` Gateway and `external-web-tls` Certificate. | `option-gateway`, `platform-aws`, `platform-azure` |
| [dns](dns/) | CoreDNS for private zones, external-dns for record automation against in-cluster CoreDNS / Route 53 / Azure DNS. | `addon-private-dns`, `platform-aws`, `platform-azure` |
| [lb](lb/) | AWS LB Controller (cloud) or MetalLB / kube-vip (metal, incus). Provides external IPs for `Service` of type `LoadBalancer`. | `platform-aws`, `platform-metal`, `platform-incus`, `platform-docker` |
| [ingress](ingress/) | Legacy nginx-ingress controller. **Not wired by current facets** — the gateway add-on is the supported path. Kept for blueprints that explicitly want classic Ingress. | (none — manual wiring) |

### Storage and data

| Add-on | Owns | Wired by |
|---|---|---|
| [csi](csi/) | Persistent storage drivers and StorageClasses — AWS EBS, Azure Disk, OpenEBS host-path, Longhorn. | `platform-aws`, `platform-azure`, `option-storage`, `option-single-node` |
| [database](database/) | CloudNativePG operator. Tenant `Cluster` resources are created by workloads; this add-on only provides the operator. | `addon-database` |
| [object-store](object-store/) | MinIO operator. The reference tenant under `resources/common` is shipped but not wired by `addon-object-store` — operators add it manually. | `addon-object-store` |

### Observability

| Add-on | Owns | Wired by |
|---|---|---|
| [observability](observability/) | Grafana, dashboards, fluentd aggregator, and pluggable log storage (stdout, Quickwit, Elasticsearch + Kibana). The fluentd aggregator is wired by `platform-base` even without the addon; Grafana and storage backends are wired by `addon-observability`. | `platform-base` (fluentd), `addon-observability` (everything else), `option-dev` (`grafana/dev` admin password patch), `option-cni` (Cilium dashboards), `option-storage` (Longhorn dashboards), `addon-database` (CNPG dashboards) |

### Examples

| Add-on | Owns | Wired by |
|---|---|---|
| [demo](demo/) | Sample workloads — a CNPG demo cluster, a live-reload static website, the Istio bookinfo app. Each toggleable independently via `demo.resources.*`. | `option-demo` |

## How facets compose

A given Kustomization name (e.g. `observability`, `pki-base`) often
appears in multiple facet entries. The Windsor harness composes them
additively — `dependsOn` and `components` lists are unioned, the path
must agree. This is how `option-cni` adds `grafana/dashboards/cilium` to
the `observability` Kustomization without redefining it, and how
`platform-base` ships the fluentd aggregator while `addon-observability`
layers in Grafana and the storage backend on the same Kustomization.

The recipes in each per-add-on README show the **materialized union** for
typical scenarios — what the merged Kustomization entry looks like after
all contributing facets resolve. Conditional `dependsOn` entries (e.g.
`policy-resources` is gated on `policies.enabled: true`) are typically
shown unconditionally for readability.

## See also

- [GUIDELINES.md](GUIDELINES.md) — timeout and interval rules.
- [contexts/_template/facets/](../contexts/_template/facets/) — the facets that wire these add-ons into a blueprint.
- [contexts/_template/schema.yaml](../contexts/_template/schema.yaml) — user-facing values.yaml schema.
- [terraform/](../terraform/) — the Terraform layer that provisions the cluster, IAM, networking, and bootstraps Flux and Cilium.
- Blueprint schema and facet syntax — https://www.windsorcli.dev/docs/blueprints/
