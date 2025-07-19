# Azure AKS Module

This module creates an Azure Kubernetes Service (AKS) cluster with configurable node pools, networking, and security settings.

## Prerequisites

The following features must be enabled in your Azure subscription before using this module:

- EncryptionAtHost feature for Microsoft.Compute provider
  ```bash
  az feature register --namespace Microsoft.Compute --name EncryptionAtHost
  az provider register --namespace Microsoft.Compute
  ```

### Subscription Requirements

This module requires a paid Azure subscription. Free tier subscriptions are not supported due to:
- Insufficient vCPU quotas
- Restricted VM sizes
- Limited node pool operations

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.36.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.36.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.5.3 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.2 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.13.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_disk_encryption_set.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/disk_encryption_set) | resource |
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_access_policy.key_vault_access_policy](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_access_policy) | resource |
| [azurerm_key_vault_access_policy.key_vault_access_policy_disk](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_access_policy) | resource |
| [azurerm_key_vault_key.key_vault_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_key) | resource |
| [azurerm_kubernetes_cluster.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.autoscaled](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_log_analytics_workspace.aks_logs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_resource_group.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [local_file.kube_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [random_string.key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_static.expiry](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_subnet.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_auto_scaler_profile"></a> [auto\_scaler\_profile](#input\_auto\_scaler\_profile) | Configuration for the AKS cluster's auto-scaler | <pre>object({<br/>    balance_similar_node_groups      = bool<br/>    max_graceful_termination_sec     = number<br/>    scale_down_delay_after_add       = string<br/>    scale_down_delay_after_delete    = string<br/>    scale_down_delay_after_failure   = string<br/>    scan_interval                    = string<br/>    scale_down_unneeded              = string<br/>    scale_down_unready               = string<br/>    scale_down_utilization_threshold = string<br/>  })</pre> | <pre>{<br/>  "balance_similar_node_groups": true,<br/>  "max_graceful_termination_sec": 600,<br/>  "scale_down_delay_after_add": "10m",<br/>  "scale_down_delay_after_delete": "10s",<br/>  "scale_down_delay_after_failure": "3m",<br/>  "scale_down_unneeded": "10m",<br/>  "scale_down_unready": "20m",<br/>  "scale_down_utilization_threshold": "0.5",<br/>  "scan_interval": "10s"<br/>}</pre> | no |
| <a name="input_automatic_upgrade_channel"></a> [automatic\_upgrade\_channel](#input\_automatic\_upgrade\_channel) | The automatic upgrade channel for the AKS cluster | `string` | `"stable"` | no |
| <a name="input_autoscaled_node_pool"></a> [autoscaled\_node\_pool](#input\_autoscaled\_node\_pool) | Configuration for the autoscaled node pool | <pre>object({<br/>    enabled                 = bool<br/>    name                    = string<br/>    vm_size                 = string<br/>    mode                    = string<br/>    os_disk_type            = string<br/>    max_pods                = number<br/>    host_encryption_enabled = bool<br/>    min_count               = number<br/>    max_count               = number<br/>  })</pre> | <pre>{<br/>  "enabled": true,<br/>  "host_encryption_enabled": true,<br/>  "max_count": 3,<br/>  "max_pods": 110,<br/>  "min_count": 1,<br/>  "mode": "User",<br/>  "name": "autoscaled",<br/>  "os_disk_type": "Managed",<br/>  "vm_size": "Standard_D2s_v3"<br/>}</pre> | no |
| <a name="input_azure_policy_enabled"></a> [azure\_policy\_enabled](#input\_azure\_policy\_enabled) | Whether to enable Azure Policy for the AKS cluster | `bool` | `true` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the AKS cluster | `string` | `null` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | `null` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig is stored | `string` | `""` | no |
| <a name="input_default_node_pool"></a> [default\_node\_pool](#input\_default\_node\_pool) | Configuration for the default node pool | <pre>object({<br/>    name                         = string<br/>    vm_size                      = string<br/>    os_disk_type                 = string<br/>    max_pods                     = number<br/>    host_encryption_enabled      = bool<br/>    min_count                    = number<br/>    max_count                    = number<br/>    node_count                   = number<br/>    only_critical_addons_enabled = bool<br/>  })</pre> | <pre>{<br/>  "host_encryption_enabled": true,<br/>  "max_count": 3,<br/>  "max_pods": 110,<br/>  "min_count": 1,<br/>  "name": "system",<br/>  "node_count": 1,<br/>  "only_critical_addons_enabled": true,<br/>  "os_disk_type": "Managed",<br/>  "vm_size": "Standard_D2s_v3"<br/>}</pre> | no |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | IP address for Kubernetes DNS service | `string` | `"10.96.0.10"` | no |
| <a name="input_endpoint_private_access"></a> [endpoint\_private\_access](#input\_endpoint\_private\_access) | Whether to enable private access to the Kubernetes API server | `bool` | `false` | no |
| <a name="input_expiration_date"></a> [expiration\_date](#input\_expiration\_date) | The expiration date for the AKS cluster's key vault | `string` | `null` | no |
| <a name="input_kubelet_client_id"></a> [kubelet\_client\_id](#input\_kubelet\_client\_id) | Client ID of the user-assigned identity to use for the kubelet. If not provided, the cluster will use the system-assigned identity. | `string` | `null` | no |
| <a name="input_kubelet_object_id"></a> [kubelet\_object\_id](#input\_kubelet\_object\_id) | Object ID of the user-assigned identity to use for the kubelet. If not provided, the cluster will use the system-assigned identity. | `string` | `null` | no |
| <a name="input_kubelet_user_assigned_identity_id"></a> [kubelet\_user\_assigned\_identity\_id](#input\_kubelet\_user\_assigned\_identity\_id) | Resource ID of the user-assigned identity to use for the kubelet. If not provided, the cluster will use the system-assigned identity. | `string` | `null` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Version of Kubernetes to use | `string` | `"1.32"` | no |
| <a name="input_local_account_disabled"></a> [local\_account\_disabled](#input\_local\_account\_disabled) | Whether to disable local accounts for the AKS cluster | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the resource | `string` | `"cluster"` | no |
| <a name="input_network_acls_default_action"></a> [network\_acls\_default\_action](#input\_network\_acls\_default\_action) | The default action for the AKS cluster's network ACLs | `string` | `"Allow"` | no |
| <a name="input_private_cluster_enabled"></a> [private\_cluster\_enabled](#input\_private\_cluster\_enabled) | Whether to enable private cluster for the AKS cluster | `bool` | `false` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether to enable public network access for the AKS cluster | `bool` | `true` | no |
| <a name="input_region"></a> [region](#input\_region) | Region for the resources | `string` | `"eastus"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group | `string` | `null` | no |
| <a name="input_role_based_access_control_enabled"></a> [role\_based\_access\_control\_enabled](#input\_role\_based\_access\_control\_enabled) | Whether to enable role-based access control for the AKS cluster | `bool` | `true` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | CIDR block for Kubernetes services | `string` | `"10.96.0.0/16"` | no |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | The SKU tier for the AKS cluster | `string` | `"Standard"` | no |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | The number of days to retain the AKS cluster's key vault | `number` | `7` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the resources | `map(string)` | `{}` | no |
| <a name="input_user_assigned_identity_ids"></a> [user\_assigned\_identity\_ids](#input\_user\_assigned\_identity\_ids) | User assigned identity IDs for the AKS cluster. If provided, the cluster will use only user-assigned identities. | `list(string)` | `[]` | no |
| <a name="input_vnet_module_name"></a> [vnet\_module\_name](#input\_vnet\_module\_name) | Name on the VNET module | `string` | `"network"` | no |
| <a name="input_vnet_subnet_id"></a> [vnet\_subnet\_id](#input\_vnet\_subnet\_id) | ID of the subnet | `string` | `null` | no |
| <a name="input_workload_autoscaler_profile"></a> [workload\_autoscaler\_profile](#input\_workload\_autoscaler\_profile) | Configuration for the AKS cluster's workload autoscaler | <pre>object({<br/>    keda_enabled                    = bool<br/>    vertical_pod_autoscaler_enabled = bool<br/>  })</pre> | <pre>{<br/>  "keda_enabled": false,<br/>  "vertical_pod_autoscaler_enabled": false<br/>}</pre> | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
