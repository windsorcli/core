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

<!-- BEGIN_INDEX -->

| Path | Purpose |
|---|---|
| [cni](/reference/blueprints/core/kustomize/cni) | Cilium as the cluster CNI, bootstrapped via Terraform and adopted by Flux. |
| [compute](/reference/blueprints/core/kustomize/compute) | Node-lifecycle controllers for elastic clusters (EKS cluster-autoscaler). |
| [csi](/reference/blueprints/core/kustomize/csi) | Persistent storage drivers and StorageClasses. AWS EBS, Azure Disk, OpenEBS host-path, and Longhorn distributed. |
| [database](/reference/blueprints/core/kustomize/database) | CloudNativePG operator for in-cluster PostgreSQL. |
| [demo](/reference/blueprints/core/kustomize/demo) | Sample applications (PostgreSQL cluster, static website, Istio bookinfo) for blueprint validation. |
| [dns](/reference/blueprints/core/kustomize/dns) | external-dns for hostname publication and (opt-in) coredns for in-cluster private DNS. |
| [gateway](/reference/blueprints/core/kustomize/gateway) | Gateway API implementation (Envoy Gateway or Cilium) and the cluster's external Gateway. |
| [lb](/reference/blueprints/core/kustomize/lb) | LoadBalancer Service implementation (AWS LB Controller, MetalLB, or kube-vip) for non-managed clusters. |
| [object-store](/reference/blueprints/core/kustomize/object-store) | MinIO Operator for in-cluster S3-compatible object storage. |
| [observability](/reference/blueprints/core/kustomize/observability) | Grafana dashboards and the cluster's log store (stdout, Quickwit, or Elasticsearch + Kibana). |
| [pki](/reference/blueprints/core/kustomize/pki) | cert-manager, trust-manager, and the cluster's ClusterIssuers (selfsigned, private CA, ACME). |
| [policy](/reference/blueprints/core/kustomize/policy) | Kyverno admission controller and the cluster's baseline ClusterPolicies. |
| [telemetry](/reference/blueprints/core/kustomize/telemetry) | kube-prometheus-stack and FluentBit for cluster-level metrics and log collection. |
<!-- END_INDEX -->
