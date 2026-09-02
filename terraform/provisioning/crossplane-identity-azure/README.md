---
title: provisioning/crossplane-identity-azure
description: Workload Identity and RBAC for Crossplane's Azure provider pods.
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
| [azurerm_federated_identity_credential.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_definition) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the AKS cluster, used to name each identity and role definition. | `string` | n/a | yes |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | AKS cluster's OIDC issuer URL, the federated credential's trust anchor. Pipe cluster/azure-aks's cluster\_oidc\_issuer\_url output. | `string` | `null` | no |
| <a name="input_postgres_resource_group_id"></a> [postgres\_resource\_group\_id](#input\_postgres\_resource\_group\_id) | ID of the dedicated resource group the postgres resource type's role assignment scopes to. Required when resources includes postgres. Pipe database/azure-postgres's resource\_group\_id output. | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | Azure region for the identities this module creates | `string` | `"eastus"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group the Crossplane identities themselves are created in. Pipe cluster/azure-aks's resource\_group\_name output. | `string` | `null` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Crossplane-managed Azure resource types to provision identity and RBAC for. Supported: postgres. | `set(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_client_ids"></a> [client\_ids](#output\_client\_ids) | Map of resource type to the identity's client ID, for the DeploymentRuntimeConfig ServiceAccount annotation. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Azure AD tenant ID shared by every identity this module creates. |
<!-- END_TF_DOCS -->