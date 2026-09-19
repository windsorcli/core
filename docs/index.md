---
title: Core
description: Core is the default blueprint Windsor ships with, covering the infrastructure, the cluster, and the workloads that run on it.
---

# Core

The default blueprint that includes base infrastructure and services. Cloud "primitives" provide storage, networking, security, and observability required to run a consistent platform across major cloud providers, virtualization platforms, and bare metal.

<!-- BEGIN_STACK_INDEX -->

## Infrastructure

### Backend — S3 · AzureRM · GCS
- [azurerm](terraform/backend/azurerm)
- [gcs](terraform/backend/gcs)
- [s3](terraform/backend/s3)

### Cluster — Talos · EKS · AKS
- [aws-eks](terraform/cluster/aws-eks)
- [azure-aks](terraform/cluster/azure-aks)
- [gcp-gke](terraform/cluster/gcp-gke)
- [talos](terraform/cluster/talos)

### CNI — Cilium bootstrap
- [cilium](terraform/cni/cilium)

### Compute — Docker · Hyper-V · Incus · Hetzner
- [docker](terraform/compute/docker)
- [hcloud](terraform/compute/hcloud)
- [hyperv](terraform/compute/hyperv)
- [incus](terraform/compute/incus)
- [vsphere](terraform/compute/vsphere)

### Database — Crossplane-managed Postgres
- [aws-rds](terraform/database/aws-rds)
- [azure-postgres](terraform/database/azure-postgres)
- [gcp-cloudsql](terraform/database/gcp-cloudsql)

### DNS — public zones
- [zone/azure-dns](terraform/dns/zone/azure-dns)
- [zone/gcp-dns](terraform/dns/zone/gcp-dns)
- [zone/hetzner](terraform/dns/zone/hetzner)
- [zone/route53](terraform/dns/zone/route53)

### GitOps — Flux
- [flux](terraform/gitops/flux)

### Network — VPC · VNet
- [aws-vpc](terraform/network/aws-vpc)
- [azure-vnet](terraform/network/azure-vnet)
- [gcp-vpc](terraform/network/gcp-vpc)

### PKI — Root CA · OIDC trust
- [ca](terraform/pki/ca)

### Provisioning — Grants Crossplane AWS access
- [crossplane-identity/aws](terraform/provisioning/crossplane-identity/aws)
- [crossplane-identity/azure](terraform/provisioning/crossplane-identity/azure)
- [crossplane-identity/gcp](terraform/provisioning/crossplane-identity/gcp)

### Workstation — local host
- [docker](terraform/workstation/docker)
- [incus](terraform/workstation/incus)

## Cluster

### CNI — Pod networking
- [cni](kustomize/cni)

### Compute — Node autoscaling
- [compute](kustomize/compute)

### CSI — Persistent storage
- [csi](kustomize/csi)

### Database — In-cluster and cloud-managed PostgreSQL
- [database](kustomize/database)

### Demo — Sample workloads for blueprint validation
- [demo](kustomize/demo)

### DNS — Automatic DNS records
- [dns](kustomize/dns)

### Gateway — Ingress traffic
- [gateway](kustomize/gateway)

### Identity — Cluster single sign-on
- [identity](kustomize/identity)

### LB — Load balancing
- [lb](kustomize/lb)

### Object store — S3-compatible storage
- [object-store](kustomize/object-store)

### Observability — Metrics dashboards
- [observability](kustomize/observability)

### PKI — TLS certificates
- [pki](kustomize/pki)

### Policy — Policy enforcement
- [policy](kustomize/policy)

### Provisioning — Cloud resource provisioning via Crossplane
- [provisioning](kustomize/provisioning)

### Telemetry — Metrics & logs
- [telemetry](kustomize/telemetry)

<!-- END_STACK_INDEX -->

## Configuration

Windsor configures Core through `values.yaml` for the current context. See the
[Values](/catalog/core/values) page for the full schema, and the
[Blueprints chapter](/blueprints/overview) for how operators author and
customize blueprints.
