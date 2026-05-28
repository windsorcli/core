---
title: Terraform module reference
description: Reference index for the Terraform modules in this blueprint.
---

# terraform/

Reference index for the Terraform modules in this blueprint. The
**Infrastructure** narrative on the docs site explains what this layer
does, when to pick which driver, and how it relates to the Cluster
layer. Links from there land here.

## Modules

| Path | Purpose |
|---|---|
| [backend/s3](backend/s3/) | Remote Terraform state on S3 + DynamoDB lock. |
| [backend/azurerm](backend/azurerm/) | Remote Terraform state on Azure Blob + native lease. |
| [workstation/docker](workstation/docker/) | Local-host Docker network + registry backing `windsor up`. |
| [workstation/incus](workstation/incus/) | Local-host Incus bridge + registry. |
| [network/aws-vpc](network/aws-vpc/) | VPC + public/private subnets + NAT for EKS. |
| [network/azure-vnet](network/azure-vnet/) | VNet + subnets for AKS. |
| [compute/docker](compute/docker/) | Talos containers on Docker. |
| [compute/hyperv](compute/hyperv/) | Talos VMs on Hyper-V (Windows host). |
| [compute/incus](compute/incus/) | Talos VMs on Incus. |
| [cluster/aws-eks](cluster/aws-eks/) | Managed Kubernetes on AWS. |
| [cluster/azure-aks](cluster/azure-aks/) | Managed Kubernetes on Azure. |
| [cluster/talos](cluster/talos/) | Self-hosted Kubernetes via Talos. |
| [cni/cilium](cni/cilium/) | Out-of-band Cilium bootstrap for Talos. |
| [dns/zone/route53](dns/zone/route53/) | Public DNS zone on AWS Route53. |
| [dns/zone/azure-dns](dns/zone/azure-dns/) | DNS zone on Azure DNS. |
| [gitops/flux](gitops/flux/) | Flux installation; hands reconciliation to the kustomize/ layer. |
