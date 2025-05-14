mock_provider "azurerm" {}

# Verifies that the module creates resources with default naming conventions and basic configuration.
# Tests the impact of module default values in minimal configuration, including:
# - Default resource naming (resource group, storage account, container)
# - Default network rules (public access allowed)
# - Default storage account settings (tier, replication, TLS version)
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
    location   = "eastus2"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "rg-tfstate-test"
    error_message = "Resource group name should follow default naming convention"
  }

  assert {
    condition     = azurerm_storage_account.this.name == "tfstatetest"
    error_message = "Storage account name should follow default naming convention"
  }

  assert {
    condition     = azurerm_storage_container.this.name == "tfstate-test"
    error_message = "Container name should follow default naming convention"
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Allow"
    error_message = "Default network rule action should be 'Allow'"
  }

  assert {
    condition     = azurerm_storage_account.this.account_tier == "Standard"
    error_message = "Default account tier should be 'Standard'"
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "LRS"
    error_message = "Default replication type should be 'LRS'"
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "Default TLS version should be 'TLS1_2'"
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values correctly override defaults for:
# - Resource naming
# - Network security rules
# - Storage account configuration
# - CMK encryption settings
run "full_configuration" {
  command = plan

  variables {
    context_id           = "test"
    location             = "eastus2"
    resource_group_name  = "custom-rg"
    storage_account_name = "customsa"
    container_name       = "customcontainer"
    allow_public_access  = false
    allowed_ip_ranges    = ["8.8.8.0/24"]
    enable_cmk           = true
    key_vault_key_id     = "https://test-keyvault.vault.azure.net/keys/test-key"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "custom-rg"
    error_message = "Resource group name should match input"
  }

  assert {
    condition     = azurerm_storage_account.this.name == "customsa"
    error_message = "Storage account name should match input"
  }

  assert {
    condition     = azurerm_storage_container.this.name == "customcontainer"
    error_message = "Container name should match input"
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny"
    error_message = "Network rule action should be 'Deny' when public access is disabled"
  }

  assert {
    condition     = contains(azurerm_storage_account.this.network_rules[0].ip_rules, "8.8.8.0/24")
    error_message = "IP rule should include allowed range"
  }

  assert {
    condition     = azurerm_user_assigned_identity.storage[0].name == "id-storage-test"
    error_message = "User-assigned identity name should follow naming convention"
  }

  assert {
    condition     = azurerm_storage_account.this.identity[0].type == "UserAssigned"
    error_message = "Storage account should have UserAssigned identity when CMK is enabled"
  }
}

# Validates that the backend configuration file is generated with correct resource names
# when a context path is provided, enabling Terraform to use the Azure backend
run "backend_config_generation" {
  command = plan

  variables {
    context_id   = "test"
    location     = "eastus2"
    context_path = "test"
  }

  assert {
    condition     = length(local_file.backend_config) == 1
    error_message = "Backend config should be generated with context path"
  }

  assert {
    condition = trimspace(local_file.backend_config[0].content) == trimspace(<<EOF
resource_group_name  = "rg-tfstate-test"
storage_account_name = "tfstatetest"
container_name      = "tfstate-test"
EOF
    )
    error_message = "Backend config should contain correct resource names"
  }
}

# Confirms that no backend configuration file is created when no context path is provided,
# preventing unnecessary file generation in the root directory
run "backend_config_without_context_path" {
  command = plan

  variables {
    context_id   = "test-nopath"
    location     = "eastus2"
    context_path = ""
  }

  assert {
    condition     = local_file.backend_config == null || length(local_file.backend_config) == 0
    error_message = "No backend config should be generated without context path"
  }
}

# Verifies that all input validation rules are enforced simultaneously, ensuring that
# invalid values for storage account names are properly caught
run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
    var.storage_account_name,
  ]
  variables {
    context_id           = "test"
    storage_account_name = "this-is-a-very-long-storage-account-name-that-exceeds-the-limit" # Too long
  }
}
