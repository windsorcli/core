---
title: network
description: Picks the cloud network foundation (VPC / VNet, subnets, NAT, optional private DNS zone) the cluster sits on.
---

# network

Provisions the cloud networking foundation the managed-cluster
modules attach to. Two sibling modules implement the same role on
different clouds; exactly one is wired in per `windsor apply`,
selected by the active facet.

| Module | Platform | Foundation |
|---|---|---|
| [`aws-vpc`](aws-vpc/) | `platform: aws` | VPC + 3 subnet tiers (public / private / isolated) per AZ, NAT, optional VPC flow logs, optional private Route53 zone |
| [`azure-vnet`](azure-vnet/) | `platform: azure` | Resource group + VNet + 3 subnet tiers, NAT gateway + public IP, route table, optional VNet-linked private DNS zone |

Both expose a parallel output shape so downstream modules can be
written generically:

| AWS output | Azure output | Consumed by |
|---|---|---|
| `vpc_id` | `vnet_id` | [`cluster/aws-eks`](../cluster/aws-eks/) / [`cluster/azure-aks`](../cluster/azure-aks/) — control plane attach |
| `private_subnet_ids` | `private_subnet_ids` | cluster — control-plane ENIs and node groups |
| `public_subnet_ids` / `isolated_subnet_ids` | same | downstream consumers (LB controllers, RDS, etc.) |
| `private_zone_id` / `private_zone_name` | same | external-dns when running in private-DNS mode (`gateway.access: private`) |

Talos clusters don't use this category — workstation-mode runtimes
provision their own networking via [`workstation/docker`](../workstation/docker/) /
[`workstation/incus`](../workstation/incus/), and bare-metal clusters
inherit operator-managed networking.

## Wiring

Both variants are wired by their platform facets with the same two
inputs:

- `cidr_block` (AWS) / `vnet_cidr` (Azure) — `network.cidr_block` from `values.yaml`. Subnets are carved out of this CIDR.
- `domain_name` — `dns.private_domain` from `values.yaml`. When set, the module creates a VPC- or VNet-attached private DNS zone for that domain. When unset, no private zone is created and `private_zone_id` / `private_zone_name` outputs are `null`.

Subnet sizing, NAT topology, AZ count, and (on AWS) flow logs all
keep their module defaults. Override per-context via tfvars at
`contexts/<context>/terraform/network.tfvars`.

## See also

- [network/aws-vpc](aws-vpc/) — AWS foundation.
- [network/azure-vnet](azure-vnet/) — Azure foundation.
- [`cluster/`](../cluster/) — managed-cluster modules that consume these outputs.
- [platform-aws.yaml](../../contexts/_template/facets/platform-aws.yaml) / [platform-azure.yaml](../../contexts/_template/facets/platform-azure.yaml) — facet wiring.
