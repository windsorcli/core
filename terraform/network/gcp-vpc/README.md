---
title: network/gcp-vpc
description: VPC, subnets, and firewall rules for GKE.
---

# network/gcp-vpc

A custom-mode VPC network with public, private, and isolated subnet tiers.
GCP subnets are regional, not zonal, so one subnet per tier already spans
every zone in the region — unlike the one-subnet-per-availability-zone
model on AWS and Azure. Cloud NAT gives the private subnet outbound
internet access with no public IP on any instance; firewall rules open the
internal, load-balancer health-check, and (optional) Identity-Aware Proxy
SSH/RDP traffic a Kubernetes cluster and its operators need, since GCP
VPCs deny all ingress by default.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_google"></a> [google](#requirement\_google) | 8.1.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.1.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_firewall.health_checks](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.iap_ingress](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.internal](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_firewall) | resource |
| [google_compute_network.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_network) | resource |
| [google_compute_router.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_router) | resource |
| [google_compute_router_nat.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_router_nat) | resource |
| [google_compute_subnetwork.isolated](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_subnetwork) | resource |
| [google_compute_subnetwork.private](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_subnetwork) | resource |
| [google_compute_subnetwork.public](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/compute_subnetwork) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | CIDR block the subnet tiers are carved from | `string` | `"10.0.0.0/16"` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | n/a | yes |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Enable VPC Flow Logs on every subnet | `bool` | `true` | no |
| <a name="input_enable_iap_ingress"></a> [enable\_iap\_ingress](#input\_enable\_iap\_ingress) | Allow SSH/RDP ingress from Identity-Aware Proxy's fixed range | `bool` | `true` | no |
| <a name="input_enable_nat"></a> [enable\_nat](#input\_enable\_nat) | Create a Cloud Router and Cloud NAT for the private subnet's outbound access | `bool` | `true` | no |
| <a name="input_isolated_subnet_cidr"></a> [isolated\_subnet\_cidr](#input\_isolated\_subnet\_cidr) | CIDR range for the isolated subnet. If not provided, a default range is derived from cidr\_block | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the VPC network | `string` | `"network"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the VPC network. If not provided, a default name will be generated | `string` | `""` | no |
| <a name="input_private_subnet_cidr"></a> [private\_subnet\_cidr](#input\_private\_subnet\_cidr) | CIDR range for the private subnet. If not provided, a default range is derived from cidr\_block | `string` | `""` | no |
| <a name="input_public_subnet_cidr"></a> [public\_subnet\_cidr](#input\_public\_subnet\_cidr) | CIDR range for the public subnet. If not provided, a default range is derived from cidr\_block | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | GCP region for the network and its subnets | `string` | `"us-central1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_isolated_subnet_id"></a> [isolated\_subnet\_id](#output\_isolated\_subnet\_id) | ID of the isolated subnet |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The ID of the VPC network |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The name of the VPC network |
| <a name="output_private_subnet_id"></a> [private\_subnet\_id](#output\_private\_subnet\_id) | ID of the private subnet |
| <a name="output_public_subnet_id"></a> [public\_subnet\_id](#output\_public\_subnet\_id) | ID of the public subnet |
| <a name="output_region"></a> [region](#output\_region) | GCP region the network and its subnets are created in |
<!-- END_TF_DOCS -->
