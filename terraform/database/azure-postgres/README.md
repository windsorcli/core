---
title: database/azure-postgres
description: Resource group, private DNS zone, NSG, and optional customer-managed key for Azure Database for PostgreSQL Flexible Server.
---
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 5.0.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_key.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_key) | resource |
| [azurerm_network_security_group.flexibleserver](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_private_dns_zone.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_resource_group.postgres](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.flexibleserver_cmk](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.key_vault_admin](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_subnet_network_security_group_association.flexibleserver](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_user_assigned_identity.flexibleserver_cmk](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_subnet_cidrs"></a> [allowed\_subnet\_cidrs](#input\_allowed\_subnet\_cidrs) | Subnet CIDRs allowed to reach Flexible Server on port 5432. Pipe network/azure-vnet's private\_subnet\_cidrs output (the AKS node subnets). | `list(string)` | `[]` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_flexibleserver_subnet_id"></a> [flexibleserver\_subnet\_id](#input\_flexibleserver\_subnet\_id) | ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. Pipe network/azure-vnet's flexibleserver\_subnet\_id output. | `string` | `null` | no |
| <a name="input_key_vault_key_id"></a> [key\_vault\_key\_id](#input\_key\_vault\_key\_id) | Existing Key Vault key ID (versionless) for Flexible Server storage encryption. Set to use a key you already manage instead of one this module creates. | `string` | `""` | no |
| <a name="input_manage_encryption_key"></a> [manage\_encryption\_key](#input\_manage\_encryption\_key) | Whether to create a dedicated Key Vault and key for Flexible Server storage encryption. False falls back to Flexible Server's platform-managed encryption. | `bool` | `true` | no |
| <a name="input_region"></a> [region](#input\_region) | Azure region for the resource group and its resources | `string` | `"eastus"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_vnet_id"></a> [vnet\_id](#input\_vnet\_id) | ID of the VNet to link the Flexible Server private DNS zone to. Pipe network/azure-vnet's vnet\_id output. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_flexibleserver_cmk_identity_id"></a> [flexibleserver\_cmk\_identity\_id](#output\_flexibleserver\_cmk\_identity\_id) | ID of the user-assigned identity Flexible Server's own identity block references to read the CMK. Null when using platform-managed encryption or a BYOK key (the operator's own identity already has access to that key). |
| <a name="output_key_vault_key_id"></a> [key\_vault\_key\_id](#output\_key\_vault\_key\_id) | Versionless Key Vault key ID for Flexible Server storage encryption. Null when using platform-managed encryption. |
| <a name="output_private_dns_zone_id"></a> [private\_dns\_zone\_id](#output\_private\_dns\_zone\_id) | ID of the private DNS zone Flexible Server's VNet-integrated mode resolves names against. |
| <a name="output_resource_group_id"></a> [resource\_group\_id](#output\_resource\_group\_id) | ID of the dedicated resource group, for scoping crossplane-identity-azure's role assignment. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the dedicated resource group every Flexible Server in this context is created in. |
<!-- END_TF_DOCS -->