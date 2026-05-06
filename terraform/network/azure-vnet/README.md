---
title: network/azure-vnet
description: Provisions the Azure resource group, VNet, subnets, NAT, and optional VNet-linked private DNS zone that an AKS cluster sits on.
---

# network/azure-vnet

Provisions the Azure networking foundation for a Windsor cluster on
AKS: a resource group, a VNet with three subnet tiers (public, private,
isolated), a NAT gateway (with public IP) attached to the private
subnets, a route table, and (optionally) a VNet-linked private DNS
zone. Its outputs are consumed by [`cluster/azure-aks`](../../cluster/azure-aks/)
(VNet + private subnets) and by external-dns when the cluster runs in
private-DNS mode (private zone ID).

This is the Azure-side parallel to [`network/aws-vpc`](../aws-vpc/) —
same role, same outputs shape (`vnet_id` / `vpc_id`,
`*_subnet_ids`, `private_zone_id`, `private_zone_name`).

## Wiring

Wired by [platform-azure.yaml](../../../contexts/_template/facets/platform-azure.yaml).
The facet only sets two inputs; the rest of the module's variables
(subnet sizing, region, vnet zones, NAT toggle) keep their module
defaults.

```yaml
terraform:
  - name: network
    path: network/azure-vnet
    dependsOn:
      - backend
    inputs:
      vnet_cidr: 10.0.0.0/16
      domain_name: prod.example.com    # optional
```

How those flow from `values.yaml`:

- `vnet_cidr` — `network.cidr_block`. Subnets are carved out of this CIDR.
- `domain_name` — `dns.private_domain`. When set, the module creates an `azurerm_private_dns_zone` named after the domain plus an `azurerm_private_dns_zone_virtual_network_link` so the zone resolves inside the VNet. When unset, no private DNS zone is created and `private_zone_id` / `private_zone_name` outputs are `null`.

The `backend` Terraform dep ensures the Azure storage backend exists
before this module's state is written.

## Security

The NAT gateway gives private subnets outbound-only egress (no public
ingress); the public subnet tier carries inbound traffic via Azure
Load Balancer or AKS-managed listeners. Network Security Groups are
not provisioned by this module — workloads or downstream modules
attach their own.

The private DNS zone is created in the same resource group as the
VNet so `cluster/azure-aks` and other consumers can reference it via
`resource_group_name` + `private_zone_id`.

## See also

- [cluster/azure-aks](../../cluster/azure-aks/) — consumes `vnet_id`, `private_subnet_ids`, `private_zone_id`, `resource_group_name`.
- [`dns` add-on](../../../kustomize/dns/) — external-dns's Azure DNS provider consumes `private_zone_id` when running in private-DNS mode (`gateway.access: private`).
- [network/aws-vpc](../aws-vpc/) — sister module for AWS.
- [platform-azure.yaml](../../../contexts/_template/facets/platform-azure.yaml) — facet wiring.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/network.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.71.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.71.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [azurerm_nat_gateway.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_private_dns_zone.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_public_ip.nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_route_table.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table) | resource |
| [azurerm_subnet.isolated](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.public](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_nat_gateway_association.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_nat_gateway_association) | resource |
| [azurerm_subnet_route_table_association.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_virtual_network.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | `null` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The domain name for the VNet-linked private DNS zone. When unset, no private zone is created. | `string` | `null` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Enable NAT Gateway for private subnets | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the resource | `string` | `"network"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region for the resources | `string` | `"eastus"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the resources | `map(string)` | `{}` | no |
| <a name="input_vnet_cidr"></a> [vnet\_cidr](#input\_vnet\_cidr) | CIDR block for the VNET | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | Name of the VNET | `string` | `null` | no |
| <a name="input_vnet_subnets"></a> [vnet\_subnets](#input\_vnet\_subnets) | Subnets to create in the VNET | `map(list(string))` | <pre>{<br/>  "isolated": [],<br/>  "private": [],<br/>  "public": []<br/>}</pre> | no |
| <a name="input_vnet_zones"></a> [vnet\_zones](#input\_vnet\_zones) | Number of availability zones to create. Only used if vnet\_subnets is not defined | `number` | `1` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_isolated_subnet_ids"></a> [isolated\_subnet\_ids](#output\_isolated\_subnet\_ids) | List of isolated subnet IDs |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | List of private subnet IDs |
| <a name="output_private_zone_id"></a> [private\_zone\_id](#output\_private\_zone\_id) | Resource ID of the VNet-linked private DNS zone created from var.domain\_name. Null when no domain\_name was supplied. |
| <a name="output_private_zone_name"></a> [private\_zone\_name](#output\_private\_zone\_name) | Name of the VNet-linked private DNS zone. Null when no domain\_name was supplied. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | List of public subnet IDs |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group holding the VNet and (when set) the private DNS zone. |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | Subscription ID resolved from the VNet resource. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | The ID of the VNet |
<!-- END_TF_DOCS -->
