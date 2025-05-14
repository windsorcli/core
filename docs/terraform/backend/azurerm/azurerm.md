## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | 4.28.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.28.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.5.3 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/4.28.0/docs/resources/resource_group) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/4.28.0/docs/resources/storage_account) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/4.28.0/docs/resources/storage_container) | resource |
| [azurerm_user_assigned_identity.storage](https://registry.terraform.io/providers/hashicorp/azurerm/4.28.0/docs/resources/user_assigned_identity) | resource |
| [local_file.backend_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_public_access"></a> [allow\_public\_access](#input\_allow\_public\_access) | Allow public access to the storage account | `bool` | `true` | no |
| <a name="input_allowed_ip_ranges"></a> [allowed\_ip\_ranges](#input\_allowed\_ip\_ranges) | List of IP ranges to allow access to the storage account | `list(string)` | `[]` | no |
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | Name of the blob container for Terraform state | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | n/a | yes |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder | `string` | `""` | no |
| <a name="input_enable_cmk"></a> [enable\_cmk](#input\_enable\_cmk) | Enable customer managed key encryption | `bool` | `false` | no |
| <a name="input_key_vault_key_id"></a> [key\_vault\_key\_id](#input\_key\_vault\_key\_id) | The ID of the Key Vault Key to use for CMK encryption | `string` | `""` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region where resources will be created | `string` | `"eastus2"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where the storage account will be created | `string` | `""` | no |
| <a name="input_storage_account_name"></a> [storage\_account\_name](#input\_storage\_account\_name) | Name of the storage account. If not provided, a default name will be generated | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

No outputs.
