mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
      object_id = "22222222-2222-2222-2222-222222222222"
    }
  }
}

variables {
  context_id           = "test"
  vnet_id              = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet-test"
  azuredb_subnet_id    = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/azuredb-test"
  allowed_subnet_cidrs = ["10.0.0.0/20"]
}

# Verifies the default path: a dedicated Key Vault and key are created.
run "manages_dedicated_key_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault.postgres) == 1
    error_message = "A dedicated Key Vault should be created by default"
  }

  assert {
    condition     = length(azurerm_key_vault_key.postgres) == 1
    error_message = "A dedicated key should be created by default"
  }

  assert {
    condition     = azurerm_key_vault.postgres[0].rbac_authorization_enabled == true
    error_message = "The dedicated Key Vault should use RBAC authorization, not access policies"
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.azuredb_cmk) == 1
    error_message = "A dedicated identity should be created for Flexible Server's own CMK access"
  }

  assert {
    condition     = azurerm_resource_group.postgres.name == "postgres-test"
    error_message = "The dedicated resource group should follow the postgres-<context_id> convention, matching network/azure-vnet and cluster/azure-aks"
  }

  assert {
    condition = alltrue([
      for tags in [
        azurerm_resource_group.postgres.tags,
        azurerm_private_dns_zone.postgres.tags,
        azurerm_private_dns_zone_virtual_network_link.postgres.tags,
        azurerm_network_security_group.azuredb.tags,
        azurerm_key_vault.postgres[0].tags,
        azurerm_user_assigned_identity.azuredb_cmk[0].tags,
      ] : tags["WindsorContextID"] == "test"
    ])
    error_message = "Every resource should carry the WindsorContextID tag, matching network/azure-vnet and cluster/azure-aks"
  }

  assert {
    condition = alltrue([
      azurerm_resource_group.postgres.tags["Name"] == azurerm_resource_group.postgres.name,
      azurerm_private_dns_zone.postgres.tags["Name"] == azurerm_private_dns_zone.postgres.name,
      azurerm_private_dns_zone_virtual_network_link.postgres.tags["Name"] == azurerm_private_dns_zone_virtual_network_link.postgres.name,
      azurerm_network_security_group.azuredb.tags["Name"] == azurerm_network_security_group.azuredb.name,
      azurerm_key_vault.postgres[0].tags["Name"] == azurerm_key_vault.postgres[0].name,
      azurerm_user_assigned_identity.azuredb_cmk[0].tags["Name"] == azurerm_user_assigned_identity.azuredb_cmk[0].name,
    ])
    error_message = "Every resource should carry a Name tag matching its own name, matching network/azure-vnet and cluster/azure-aks"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.postgres.virtual_network_id == var.vnet_id
    error_message = "The private DNS zone should link to the supplied VNet"
  }

  assert {
    condition     = azurerm_subnet_network_security_group_association.azuredb.subnet_id == var.azuredb_subnet_id
    error_message = "The NSG should attach to the delegated Flexible Server subnet"
  }

  assert {
    condition     = contains(azurerm_network_security_group.azuredb.security_rule[*].destination_port_range, "5432")
    error_message = "The NSG should allow inbound on the Postgres port"
  }

  assert {
    condition     = contains(flatten(azurerm_network_security_group.azuredb.security_rule[*].source_address_prefixes), "10.0.0.0/20")
    error_message = "The NSG should scope Postgres ingress to the AKS node subnets, not the whole VNet"
  }
}

# Verifies manage_encryption_key = false skips the dedicated Key Vault and
# falls back to Flexible Server's platform-managed encryption.
run "falls_back_to_platform_managed_encryption_when_unmanaged" {
  command = plan

  variables {
    manage_encryption_key = false
  }

  assert {
    condition     = length(azurerm_key_vault.postgres) == 0
    error_message = "No dedicated Key Vault should be created when manage_encryption_key is false"
  }

  assert {
    condition     = output.key_id == ""
    error_message = "key_id output should be empty when using platform-managed encryption"
  }

  assert {
    condition     = output.azuredb_cmk_identity_id == null
    error_message = "azuredb_cmk_identity_id output should be null when using platform-managed encryption"
  }
}

# Verifies an explicit key_id skips creating a dedicated Key Vault entirely,
# even when manage_encryption_key is left at its default.
run "byok_key_id_skips_dedicated_key" {
  command = plan

  variables {
    key_id = "https://byok.vault.azure.net/keys/postgres/abcd1234"
  }

  assert {
    condition     = length(azurerm_key_vault.postgres) == 0
    error_message = "No dedicated Key Vault should be created when key_id supplies an existing key"
  }

  assert {
    condition     = output.key_id == "https://byok.vault.azure.net/keys/postgres/abcd1234"
    error_message = "key_id output should pass the supplied key ID through unchanged"
  }

  assert {
    condition     = output.azuredb_cmk_identity_id == null
    error_message = "No CMK identity is created for a BYOK key; the operator's own key access already covers it"
  }
}

# Verifies vnet_id is required.
run "vnet_id_required" {
  command = plan

  variables {
    vnet_id = null
  }

  expect_failures = [var.vnet_id]
}

# Verifies azuredb_subnet_id is required.
run "azuredb_subnet_id_required" {
  command = plan

  variables {
    azuredb_subnet_id = null
  }

  expect_failures = [var.azuredb_subnet_id]
}

# Verifies a destroy operation relaxes the sibling-input validations, so a
# plan can still be produced once network/azure-vnet is gone.
run "destroy_operation_relaxes_sibling_input_validation" {
  command = plan

  variables {
    operation            = "destroy"
    vnet_id              = null
    azuredb_subnet_id    = null
    allowed_subnet_cidrs = []
  }
}

# Verifies a caller-supplied var.tags entry can't override the module's own
# WindsorContextID/Name values.
run "var_tags_cannot_override_windsor_context_id_or_name" {
  command = plan

  variables {
    tags = {
      WindsorContextID = "not-the-real-context"
      Name             = "not-the-real-name"
    }
  }

  assert {
    condition     = azurerm_resource_group.postgres.tags["WindsorContextID"] == "test"
    error_message = "A caller-supplied WindsorContextID in var.tags must not override the module's own value"
  }

  assert {
    condition     = azurerm_resource_group.postgres.tags["Name"] == azurerm_resource_group.postgres.name
    error_message = "A caller-supplied Name in var.tags must not override the resource's own Name tag"
  }
}
