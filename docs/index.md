---
title: Core
description: The default Windsor blueprint — the complete, self-hosted platform most projects start from, on any target.
---

# Core

The default Windsor blueprint — and where most projects start. A complete,
self-hosted platform you deploy on any target and make your own.

## Infrastructure

### Backend — S3 · AzureRM
- [backend](terraform/backend)

### Network — VPC · VNet
- [network](terraform/network)

### Workstation — local host
- [workstation](terraform/workstation)

### Compute — Docker · Hyper-V · Incus
- [compute](terraform/compute)

### Cluster — Talos · EKS · AKS
- [cluster](terraform/cluster)

### CNI — Cilium bootstrap
- [cni](terraform/cni)

### GitOps — Flux
- [gitops](terraform/gitops)

### DNS — public zones
- [dns](terraform/dns)

## Cluster

### CNI — Cilium
- [cni](kustomize/cni)

### CSI — EBS · Azure Disk · OpenEBS · Longhorn
- [csi](kustomize/csi)

### PKI — cert-manager
- [pki](kustomize/pki)

### Policy — Kyverno
- [policy](kustomize/policy)

### Gateway — Gateway API
- [gateway](kustomize/gateway)

### LB — MetalLB · kube-vip · AWS LB
- [lb](kustomize/lb)

### DNS — external-dns
- [dns](kustomize/dns)

### Database — CloudNativePG
- [database](kustomize/database)

### Object store — MinIO
- [object-store](kustomize/object-store)

### Observability — Grafana
- [observability](kustomize/observability)

### Telemetry — Prometheus · FluentBit
- [telemetry](kustomize/telemetry)

### Demo — sample apps
- [demo](kustomize/demo)

## Configuration

Core is configured through `values.yaml` for the current context. See the
[Values](/catalog/core/values) page for the full schema, and the
[Blueprints chapter](/blueprints/overview) for how blueprints are authored
and customized.
