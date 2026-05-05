## Reference

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
