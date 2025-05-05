#---------------------------------------------------------------------------------------------------
# Versions
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.27.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Azure Provider configuration
#-----------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
  use_oidc        = var.azure_use_oidc
  client_id       = var.azure_client_id
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_deleted_keys_on_destroy = true
      recover_soft_deleted_keys          = true
    }
  }
}

data "azurerm_client_config" "current" {}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Groups
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "aks" {
  name     = "${var.prefix}-aks-rg"
  location = var.region
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  kubeconfig_path = "${var.context_path}/.kube/config"
}

#-----------------------------------------------------------------------------------------------------------------------
# Key Vault
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_key_vault" "key_vault" {
  name                        = "${var.prefix}-keyvault"
  location                    = azurerm_resource_group.aks.location
  resource_group_name         = azurerm_resource_group.aks.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium"
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
  soft_delete_retention_days  = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Delete",
      "Get",
      "Purge",
      "Recover",
      "Update",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]

    secret_permissions = [
      "Set",
    ]
  }
}

resource "azurerm_key_vault_access_policy" "key_vault_access_policy_disk" {
  key_vault_id = azurerm_key_vault.key_vault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_disk_encryption_set.main.identity.0.principal_id

  key_permissions = [
    "Get",
    "Decrypt",
    "Encrypt",
    "Sign",
    "UnwrapKey",
    "Verify",
    "WrapKey",
  ]

  depends_on = [
    azurerm_disk_encryption_set.main
  ]
}

resource "random_string" "key_vault_key_name" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}

resource "azurerm_key_vault_key" "key_vault_key" {
  name         = "${var.prefix}-key-${random_string.key_vault_key_name.result}"
  key_vault_id = azurerm_key_vault.key_vault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }
}

resource "azurerm_disk_encryption_set" "main" {
  name                = "${var.prefix}-des-${random_string.key_vault_key_name.result}"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  key_vault_key_id    = azurerm_key_vault_key.key_vault_key.id

  identity {
    type = "SystemAssigned"
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Log Analytics Workspace
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "aks_logs" {
  name                = "${var.prefix}-aks-logs"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

#-----------------------------------------------------------------------------------------------------------------------
# AKS Cluster
#-----------------------------------------------------------------------------------------------------------------------

data "azurerm_subnet" "private" {
  name                 = "${var.prefix}-priv-subnet-1"
  resource_group_name  = "${var.prefix}-vpc-rg"
  virtual_network_name = "${var.prefix}-vpc"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "${var.prefix}-${var.cluster_name}"
  location                          = azurerm_resource_group.aks.location
  resource_group_name               = azurerm_resource_group.aks.name
  dns_prefix                        = "${var.prefix}-${var.cluster_name}"
  kubernetes_version                = var.kubernetes_version
  role_based_access_control_enabled = var.role_based_access_control_enabled
  automatic_upgrade_channel         = var.automatic_upgrade_channel
  sku_tier                          = var.sku_tier
  # checkov:skip=CKV_AZURE_6: this feature is in preview
  # api_server_authorized_ip_ranges   = var.api_server_authorized_ip_ranges
  private_cluster_enabled = var.private_cluster_enabled
  disk_encryption_set_id  = azurerm_disk_encryption_set.main.id
  # checkov:skip=CKV_AZURE_116: this replaces the addon_profile
  azure_policy_enabled   = var.azure_policy_enabled
  local_account_disabled = var.local_account_disabled

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  default_node_pool {
    name                         = "system"
    node_count                   = 1
    vm_size                      = "Standard_D2s_v3"
    vnet_subnet_id               = data.azurerm_subnet.private.id
    orchestrator_version         = var.kubernetes_version
    only_critical_addons_enabled = true
    # checkov:skip=CKV_AZURE_226: we are using the managed disk type to reduce costs
    os_disk_type            = var.os_disk_type
    host_encryption_enabled = var.host_encryption_enabled
    max_pods                = var.max_pods
  }

  auto_scaler_profile {
    balance_similar_node_groups      = var.auto_scaler_profile["balance_similar_node_groups"]
    max_graceful_termination_sec     = var.auto_scaler_profile["max_graceful_termination_sec"]
    scale_down_delay_after_add       = var.auto_scaler_profile["scale_down_delay_after_add"]
    scale_down_delay_after_delete    = var.auto_scaler_profile["scale_down_delay_after_delete"]
    scale_down_delay_after_failure   = var.auto_scaler_profile["scale_down_delay_after_failure"]
    scan_interval                    = var.auto_scaler_profile["scan_interval"]
    scale_down_unneeded              = var.auto_scaler_profile["scale_down_unneeded"]
    scale_down_unready               = var.auto_scaler_profile["scale_down_unready"]
    scale_down_utilization_threshold = var.auto_scaler_profile["scale_down_utilization_threshold"]
  }

  workload_autoscaler_profile {
    keda_enabled                    = var.workload_autoscaler_profile["keda_enabled"]
    vertical_pod_autoscaler_enabled = var.workload_autoscaler_profile["vertical_pod_autoscaler_enabled"]
  }

  network_profile {
    network_policy = "azure"
    network_plugin = "azure"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_logs.id
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "autoscaled" {
  name                  = "autoscaled"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D2s_v3"
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = var.min_count
  max_count             = var.max_count
  vnet_subnet_id        = data.azurerm_subnet.private.id
  orchestrator_version  = var.kubernetes_version
  # checkov:skip=CKV_AZURE_226: we are using the managed disk type to reduce costs
  os_disk_type            = var.os_disk_type
  max_pods                = var.max_pods
  host_encryption_enabled = var.host_encryption_enabled
}

resource "local_file" "kube_config" {
  content  = azurerm_kubernetes_cluster.main.kube_config_raw
  filename = local.kubeconfig_path
}
