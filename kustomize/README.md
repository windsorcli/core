---
title: Kustomize add-ons
description: Index of the cluster add-ons that Flux reconciles via Kustomization CRs.
---

# kustomize/

Each subdirectory here is a cluster add-on that Flux reconciles via a
Kustomization CR composed from a Windsor facet. The on-cluster
operator-facing slice (Helm releases, ClusterPolicies, etc.) lives
here; the IaC slice (cloud accounts, networks, clusters) lives under
[`terraform/`](../terraform/).

## Add-ons

| Add-on | Purpose |
|---|---|
| [cni](cni/) | Container networking. Cilium with optional Gateway API, L2 announcer, Hubble. |
| [csi](csi/) | Persistent storage drivers and StorageClasses. AWS EBS, Azure Disk, OpenEBS, Longhorn. |
| [database](database/) | CloudNativePG operator for in-cluster PostgreSQL. |
| [demo](demo/) | Sample applications (Postgres cluster, static site, Istio bookinfo) for blueprint validation. |
| [dns](dns/) | external-dns for hostname publication; coredns + etcd for in-cluster private DNS. |
| [gateway](gateway/) | Gateway API implementation (Envoy Gateway or Cilium) and the cluster's external Gateway. |
| [gitops](gitops/) | system-gitops namespace + Flux webhook receiver scaffolding (operator-wired via Terraform, not via kustomize facets). |
| [ingress](ingress/) | Reserved for legacy `Ingress`-style routing (currently unused — operators route via the gateway add-on). |
| [lb](lb/) | LoadBalancer Service provider: aws-lb-controller, MetalLB, or kube-vip. |
| [object-store](object-store/) | MinIO Operator for in-cluster S3-compatible object storage. |
| [observability](observability/) | Grafana dashboards and log store (stdout, Quickwit, or Elasticsearch + Kibana). |
| [pki](pki/) | cert-manager, trust-manager, and the cluster's ClusterIssuers. |
| [policy](policy/) | Kyverno admission controller and the baseline ClusterPolicies. |
| [telemetry](telemetry/) | kube-prometheus-stack and FluentBit for cluster-level metrics and log collection. |

## Conventions

Every add-on README follows a fixed structure: a short intro, an
Architecture Mermaid diagram, Recipes showing the canonical facet
entries, and a region between `<!-- BEGIN_KUSTOMIZE_DOCS -->` /
`<!-- END_KUSTOMIZE_DOCS -->` containing auto-generated Substitutions /
Components / Dependencies tables. The tables are materialized from
each add-on's `.docs.yaml` descriptor by [scripts/kustomize-docs.sh](../scripts/kustomize-docs.sh)
(`task docs:kustomize`). CI fails the build on drift (`task
docs:kustomize:check`).

**Single- vs multi-facet add-ons.** Several add-ons split across two
Kustomization paths so Flux can install CRDs (`<addon>-base`) before
the cluster-resource CRs that depend on them (`<addon>-resources`).
This pattern is used by `gateway`, `lb`, `pki`, `policy`, and
`telemetry`. Their `.docs.yaml` declares a `facets:` array and tags
each component with the facet it belongs to; the generator renders
one Components sub-table per facet.

For the underlying timeout / interval guidance on the Kustomization /
HelmRelease CRs, see [GUIDELINES.md](GUIDELINES.md).

## Related

- [terraform/](../terraform/) — cloud-account, network, and cluster modules that bootstrap the platform this add-on tree runs on.
- [contexts/_template/facets/](../contexts/_template/facets/) — facet definitions that compose these add-ons into deployable bundles.
- Blueprint schema and facet syntax — https://www.windsorcli.dev/docs/blueprints/
