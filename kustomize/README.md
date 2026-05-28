---
title: Kustomize add-on reference
description: Reference index for the Kustomize add-ons in this blueprint.
---

# kustomize/

Reference index for the Kustomize add-ons in this blueprint. The
**Cluster** narrative on the docs site explains what this layer does,
which add-ons are required vs. opt-in, and how the schema fields drive
composition. Links from there land here.

## Add-ons

| Path | Purpose |
|---|---|
| [cni](cni/) | Container networking. Cilium with optional Gateway API, L2 announcer, Hubble. |
| [csi](csi/) | Persistent storage drivers and StorageClasses. AWS EBS, Azure Disk, OpenEBS, Longhorn. |
| [database](database/) | CloudNativePG operator for in-cluster PostgreSQL. |
| [demo](demo/) | Sample applications (Postgres cluster, static site, Istio bookinfo) for blueprint validation. |
| [dns](dns/) | external-dns for hostname publication; coredns + etcd for in-cluster private DNS. |
| [gateway](gateway/) | Gateway API implementation (Envoy Gateway or Cilium) and the cluster's external Gateway. |
| [lb](lb/) | LoadBalancer Service provider: aws-lb-controller, MetalLB, or kube-vip. |
| [object-store](object-store/) | MinIO Operator for in-cluster S3-compatible object storage. |
| [observability](observability/) | Grafana dashboards and log store (stdout, Quickwit, or Elasticsearch + Kibana). |
| [pki](pki/) | cert-manager, trust-manager, and the cluster's ClusterIssuers. |
| [policy](policy/) | Kyverno admission controller and the baseline ClusterPolicies. |
| [telemetry](telemetry/) | kube-prometheus-stack and FluentBit for cluster-level metrics and log collection. |
