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

<!-- BEGIN_INDEX -->

| Path | Purpose |
|---|---|
| [backend](/reference/blueprints/core/terraform/backend) | Remote Terraform state for cloud contexts (S3, AzureRM). |
| [backend/azurerm](/reference/blueprints/core/terraform/backend/azurerm) | Remote Terraform state on Azure Blob + native lease. |
| [backend/s3](/reference/blueprints/core/terraform/backend/s3) | Remote Terraform state on S3 + DynamoDB lock. |
| [cluster](/reference/blueprints/core/terraform/cluster) | Kubernetes control plane provisioning across Talos, EKS, and AKS. |
| [cluster/aws-eks](/reference/blueprints/core/terraform/cluster/aws-eks) | Managed Kubernetes control plane on AWS. |
| [cluster/aws-eks/additions](/reference/blueprints/core/terraform/cluster/aws-eks/additions) | system-dns namespace and external-dns ConfigMap for EKS. |
| [cluster/azure-aks](/reference/blueprints/core/terraform/cluster/azure-aks) | Managed Kubernetes control plane on Azure. |
| [cluster/talos](/reference/blueprints/core/terraform/cluster/talos) | Self-hosted Kubernetes control plane via the Talos API. |
| [cluster/talos/config](/reference/blueprints/core/terraform/cluster/talos/config) | Per-node Talos machine config + CIDATA seeds. |
| [cluster/talos/extensions](/reference/blueprints/core/terraform/cluster/talos/extensions) | Talos image build with system extensions. |
| [cni](/reference/blueprints/core/terraform/cni) | Out-of-band Cilium bootstrap for Talos clusters before Flux. |
| [cni/cilium](/reference/blueprints/core/terraform/cni/cilium) | Out-of-band Cilium bootstrap for Talos clusters. |
| [compute](/reference/blueprints/core/terraform/compute) | Local Talos compute substrate across Docker, Hyper-V, and Incus. |
| [compute/docker](/reference/blueprints/core/terraform/compute/docker) | Talos containers on Docker. |
| [compute/hyperv](/reference/blueprints/core/terraform/compute/hyperv) | Talos VMs on Hyper-V (Windows host). |
| [compute/incus](/reference/blueprints/core/terraform/compute/incus) | Talos VMs on Incus. |
| [dns](/reference/blueprints/core/terraform/dns) | Public DNS zones for ACME certificates and external-dns. |
| [dns/zone/azure-dns](/reference/blueprints/core/terraform/dns/zone/azure-dns) | DNS zone on Azure DNS. |
| [dns/zone/route53](/reference/blueprints/core/terraform/dns/zone/route53) | Public DNS zone on AWS Route53. |
| [gitops](/reference/blueprints/core/terraform/gitops) | Flux installation that hands reconciliation to the kustomize layer. |
| [gitops/flux](/reference/blueprints/core/terraform/gitops/flux) | Flux installation; hands reconciliation to the kustomize/ layer. |
| [network](/reference/blueprints/core/terraform/network) | Cloud network fabric for managed Kubernetes clusters. |
| [network/aws-vpc](/reference/blueprints/core/terraform/network/aws-vpc) | VPC + public/private subnets + NAT for EKS. |
| [network/azure-vnet](/reference/blueprints/core/terraform/network/azure-vnet) | VNet + subnets for AKS. |
| [workstation](/reference/blueprints/core/terraform/workstation) | Local-host networking, registry, and DNS for developer clusters. |
| [workstation/docker](/reference/blueprints/core/terraform/workstation/docker) | Local-host Docker network + registry. |
| [workstation/incus](/reference/blueprints/core/terraform/workstation/incus) | Local-host Incus bridge + registry. |
<!-- END_INDEX -->
