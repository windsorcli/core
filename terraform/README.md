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
| [backend](backend/) | Remote Terraform state for cloud contexts (S3, AzureRM). |
| [backend/azurerm](backend/azurerm/) | Remote Terraform state on Azure Blob + native lease. |
| [backend/s3](backend/s3/) | Remote Terraform state on S3 + DynamoDB lock. |
| [cluster](cluster/) | Kubernetes control plane provisioning across Talos, EKS, and AKS. |
| [cluster/aws-eks](cluster/aws-eks/) | Managed Kubernetes control plane on AWS. |
| [cluster/aws-eks/additions](cluster/aws-eks/additions/) | system-dns namespace and external-dns ConfigMap for EKS. |
| [cluster/azure-aks](cluster/azure-aks/) | Managed Kubernetes control plane on Azure. |
| [cluster/talos](cluster/talos/) | Self-hosted Kubernetes control plane via the Talos API. |
| [cluster/talos/config](cluster/talos/config/) | Per-node Talos machine config + CIDATA seeds. |
| [cluster/talos/extensions](cluster/talos/extensions/) | Talos image build with system extensions. |
| [cni](cni/) | Out-of-band Cilium bootstrap for Talos clusters before Flux. |
| [cni/cilium](cni/cilium/) | Out-of-band Cilium bootstrap for Talos clusters. |
| [compute](compute/) | Local Talos compute substrate across Docker, Hyper-V, and Incus. |
| [compute/docker](compute/docker/) | Talos containers on Docker. |
| [compute/hcloud](compute/hcloud/) | Provisions Talos Linux nodes on Hetzner Cloud. |
| [compute/hyperv](compute/hyperv/) | Talos VMs on Hyper-V (Windows host). |
| [compute/incus](compute/incus/) | Talos VMs on Incus. |
| [dns](dns/) | Public DNS zones for ACME certificates and external-dns. |
| [dns/zone/azure-dns](dns/zone/azure-dns/) | DNS zone on Azure DNS. |
| [dns/zone/hetzner](dns/zone/hetzner/) | Creates a primary Hetzner DNS zone via the official hcloud provider. |
| [dns/zone/route53](dns/zone/route53/) | Public DNS zone on AWS Route53. |
| [gitops](gitops/) | Flux installation that hands reconciliation to the kustomize layer. |
| [gitops/flux](gitops/flux/) | Flux installation; hands reconciliation to the kustomize/ layer. |
| [network](network/) | Cloud network fabric for managed Kubernetes clusters. |
| [network/aws-vpc](network/aws-vpc/) | VPC + public/private subnets + NAT for EKS. |
| [network/azure-vnet](network/azure-vnet/) | VNet + subnets for AKS. |
| [workstation](workstation/) | Local-host networking, registry, and DNS for developer clusters. |
| [workstation/docker](workstation/docker/) | Local-host Docker network + registry. |
| [workstation/incus](workstation/incus/) | Local-host Incus bridge + registry. |
<!-- END_INDEX -->
