terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.40.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#---------------------------------------------------------------------------------------------------
# Storage Account Creation
# This section creates the Azure Storage Account used for storing Terraform state.
# It ensures that the storage account is unique per subscription and resource group.
#---------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "this" {
  # checkov:skip=CKV_AZURE_33:Not needed for terraform backend
  # checkov:skip=CKV_AZURE_35:Network rules are configured via network_rules block
  # checkov:skip=CKV_AZURE_43:Storage account name is managed by variables
  # checkov:skip=CKV_AZURE_206:Using LRS for terraform state is acceptable
  # checkov:skip=CKV2_AZURE_33:Private endpoint not needed for terraform backend
  # checkov:skip=CKV2_AZURE_40:Shared key auth needed for terraform backend
  # checkov:skip=CKV2_AZURE_47:Container access type is set to private
  # checkov:skip=CKV_AZURE_190:Public access is disabled via network rules
  # checkov:skip=CKV2_AZURE_41:SAS expiration not needed for terraform backend
  # checkov:skip=CKV2_AZURE_1:CMK not needed for terraform state
  # checkov:skip=CKV_AZURE_59:Public access needed for terraform backend
  name                     = var.storage_account_name != "" ? var.storage_account_name : local.default_storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  dynamic "identity" {
    for_each = var.enable_cmk ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.storage[0].id]
    }
  }

  # Configure customer managed key if enabled
  dynamic "customer_managed_key" {
    for_each = var.enable_cmk && var.key_vault_key_id != "" ? [1] : []
    content {
      key_vault_key_id          = var.key_vault_key_id
      user_assigned_identity_id = azurerm_user_assigned_identity.storage[0].principal_id
    }
  }

  # Configure blob properties
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  # Configure SAS token expiration
  sas_policy {
    expiration_period = "1.00:00:00"
  }

  tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
    }
  )

  network_rules {
    default_action = var.allow_public_access ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_ranges
  }
}

#---------------------------------------------------------------------------------------------------
# Storage Container Creation
# This section creates the blob container within the storage account for Terraform state files.
#---------------------------------------------------------------------------------------------------

resource "azurerm_storage_container" "this" {
  # checkov:skip=CKV2_AZURE_21:Logging configured at storage account level
  name                  = local.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

#---------------------------------------------------------------------------------------------------
# Local Variables
# This section defines local variables for naming conventions and configuration.
#---------------------------------------------------------------------------------------------------

locals {
  default_storage_account_name = var.storage_account_name != "" ? var.storage_account_name : replace(lower("tfstate${var.context_id}"), "/[^a-z0-9]/", "")
  resource_group_name          = var.resource_group_name != "" ? var.resource_group_name : "rg-tfstate-${var.context_id}"
  container_name               = var.container_name != "" ? var.container_name : "tfstate-${var.context_id}"
}

#---------------------------------------------------------------------------------------------------
# Backend Configuration File
# This section generates the backend configuration file for Terraform.
#---------------------------------------------------------------------------------------------------

resource "local_file" "backend_config" {
  count = trim(var.context_path, " ") != "" ? 1 : 0
  content = templatefile("${path.module}/templates/backend.tftpl", {
    resource_group_name  = local.resource_group_name
    storage_account_name = azurerm_storage_account.this.name
    container_name       = azurerm_storage_container.this.name
  })
  filename = "${var.context_path}/terraform/backend.tfvars"
}

# User-assigned identity for CMK
resource "azurerm_user_assigned_identity" "storage" {
  count               = var.enable_cmk ? 1 : 0
  name                = "id-storage-${var.context_id}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
}
