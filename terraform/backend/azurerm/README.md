---
title: backend/azurerm
description: Creates the Azure resource group, storage account, and blob container Windsor uses as the Terraform remote state backend on Azure.
---

# backend/azurerm

Bootstraps Windsor's Terraform remote state backend on Azure. This
module creates a resource group, a storage account (versioning on,
LRS, TLS 1.2 minimum), a private blob container for state, and writes
a `backend.tfvars` snippet into the context so subsequent Terraform
modules know where to read and write state.

It runs first on `platform: azure` — every other Azure-side module
declares `dependsOn: backend` so the storage account exists before
anything tries to write to it.

The AzureRM backend uses native blob lease locking; no external lock
table is provisioned.

## Wiring

Wired by [platform-azure.yaml](../../../contexts/_template/facets/platform-azure.yaml).
The facet passes no explicit inputs; `context_path` and `context_id`
are auto-injected by the Windsor CLI based on the active context.

```yaml
terraform:
  - name: backend
    path: backend/azurerm
    # no inputs — context_path and context_id come from the CLI
```

The module's other variables (`location`, `resource_group_name`,
`storage_account_name`, `container_name`, `allow_public_access`,
`allowed_ip_ranges`, `enable_cmk`, `key_vault_key_id`, `tags`) are
not driven by the facet and keep their module defaults. Override any
of them via tfvars (see [Reference](#reference)) — typical overrides
are `location` (defaults to `eastus2`) and `allow_public_access` /
`allowed_ip_ranges` to lock the storage account down to known CIDRs.

## Security

The storage account is created with `min_tls_version = "TLS1_2"`,
versioning enabled, and 7-day soft-delete retention on both blobs and
containers. The state container itself uses `private` access — no
anonymous reads.

By default `allow_public_access = true`, which translates to the
storage account's network rule `default_action = "Allow"`. This keeps
bootstrap simple but leaves the state account reachable from any
network the storage firewall would otherwise block. Set
`allow_public_access = false` and populate `allowed_ip_ranges` to
restrict it.

Optional CMK encryption: `enable_cmk = true` plus `key_vault_key_id`
attaches a user-assigned managed identity (`azurerm_user_assigned_identity.storage`)
and configures `customer_managed_key` on the storage account. Both
must be set for CMK to take effect; `enable_cmk` alone with no key ID
is a no-op.

The storage account's `network_rules` block is wrapped in
`lifecycle.ignore_changes` to work around an azurerm v4 quirk where
the provider re-proposes the block on every plan. Once-at-create-time
configuration is the assumed posture for state-backend rules; if you
need to change the firewall later, edit the rules out-of-band or
remove the ignore.

## See also

- [network/azure-vnet](../../network/azure-vnet/) — declares `dependsOn: backend` so the VNet's state lives in this account.
- [cluster/azure-aks](../../cluster/azure-aks/) — same pattern: depends on this module for the state backend.
- [backend/s3](../s3/) — sister module for AWS.
- [platform-azure.yaml](../../../contexts/_template/facets/platform-azure.yaml) — facet wiring.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/backend.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | 4.71.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.71.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.6.1 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/4.71.0/docs/resources/resource_group) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/4.71.0/docs/resources/storage_account) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/4.71.0/docs/resources/storage_container) | resource |
| [azurerm_user_assigned_identity.storage](https://registry.terraform.io/providers/hashicorp/azurerm/4.71.0/docs/resources/user_assigned_identity) | resource |
| [local_file.backend_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |

### Inputs

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

### Outputs

No outputs.
<!-- END_TF_DOCS -->