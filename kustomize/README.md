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
| [cni](cni/) | Cilium as the cluster CNI, bootstrapped via Terraform and adopted by Flux. |
| [compute](compute/) | Node-lifecycle controllers for elastic clusters (EKS cluster-autoscaler). |
| [csi](csi/) | Persistent storage drivers and StorageClasses. AWS EBS, Azure Disk, OpenEBS host-path, and Longhorn distributed. |
| [database](database/) | CloudNativePG operator for in-cluster PostgreSQL. |
| [demo](demo/) | Sample applications (PostgreSQL cluster, static website, Istio bookinfo) for blueprint validation. |
| [dns](dns/) | external-dns for hostname publication and (opt-in) coredns for in-cluster private DNS. |
| [gateway](gateway/) | Gateway API implementation (Envoy Gateway or Cilium) and the cluster's external Gateway. |
| [identity](identity/) | Keycloak identity provider (OIDC / SSO) via the Keycloak Operator. |
| [lb](lb/) | LoadBalancer Service implementation (AWS LB Controller, MetalLB, or kube-vip) for non-managed clusters. |
| [object-store](object-store/) | MinIO Operator for in-cluster S3-compatible object storage. |
| [observability](observability/) | Grafana dashboards and the cluster's log store (stdout, Quickwit, or Elasticsearch + Kibana). |
| [pki](pki/) | cert-manager, trust-manager, and the cluster's ClusterIssuers (selfsigned, private CA, ACME). |
| [policy](policy/) | Kyverno admission controller and the cluster's baseline ClusterPolicies. |
| [telemetry](telemetry/) | kube-prometheus-stack and FluentBit for cluster-level metrics and log collection. |
<!-- END_INDEX -->
