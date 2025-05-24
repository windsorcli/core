#---------------------------------------------------------------------------------------------------
# Versions
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.30.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Azure Provider configuration
#-----------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
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

#-----------------------------------------------------------------------------------------------------------------------
# Data Sources
#-----------------------------------------------------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

data "azurerm_subnet" "private" {
  count                = var.vnet_subnet_id == null ? 1 : 0
  name                 = "private-1-${var.context_id}"
  resource_group_name  = "${var.vnet_module_name}-${var.context_id}"
  virtual_network_name = "${var.vnet_module_name}-${var.context_id}"
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  kubeconfig_path = "${var.context_path}/.kube/config"
  rg_name         = var.resource_group_name == null ? "${var.name}-${var.context_id}" : var.resource_group_name
  cluster_name    = var.cluster_name == null ? "${var.name}-${var.context_id}" : var.cluster_name
  tags = merge({
    WindsorContextID = var.context_id
  }, var.tags)
}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Groups
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "aks" {
  name     = local.rg_name
  location = var.region
  tags = merge({
    Name = local.rg_name
  }, local.tags)
}

#-----------------------------------------------------------------------------------------------------------------------
# Key Vault
#-----------------------------------------------------------------------------------------------------------------------

resource "random_string" "key" {
  length  = 3
  special = false
  upper   = false
}

resource "azurerm_key_vault" "key_vault" {
  # checkov:skip=CKV2_AZURE_32: We are using a public cluster for testing, there is no need for private endpoints.
  name                        = "${var.name}-${var.context_id}-${random_string.key.result}"
  location                    = azurerm_resource_group.aks.location
  resource_group_name         = azurerm_resource_group.aks.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium"
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
  soft_delete_retention_days  = var.soft_delete_retention_days
  # checkov:skip=CKV_AZURE_189: We are using a public cluster for testing
  # private services are encouraged for production
  public_network_access_enabled = var.public_network_access_enabled

  # checkov:skip=CKV_AZURE_109: We are using a public cluster for testing
  # private services are encouraged for production. Change to "Deny" for production.
  network_acls {
    default_action = var.network_acls_default_action
    bypass         = "AzureServices"
  }
  tags = merge({
    Name = "${var.name}-${var.context_id}-${random_string.key.result}"
  }, local.tags)
}

resource "azurerm_key_vault_access_policy" "key_vault_access_policy" {
  key_vault_id = azurerm_key_vault.key_vault.id

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

resource "time_static" "expiry" {}

resource "azurerm_key_vault_key" "key_vault_key" {
  name            = "${var.name}-${var.context_id}-${random_string.key.result}"
  key_vault_id    = azurerm_key_vault.key_vault.id
  key_type        = "RSA-HSM"
  key_size        = 2048
  expiration_date = var.expiration_date != null ? var.expiration_date : timeadd(time_static.expiry.rfc3339, "8760h")

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

  depends_on = [
    azurerm_key_vault_access_policy.key_vault_access_policy
  ]
}

resource "azurerm_disk_encryption_set" "main" {
  name                = "${var.name}-${var.context_id}-${random_string.key.result}"
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
  name                = "${var.name}-${var.context_id}"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = merge({
    Name = "${var.name}-${var.context_id}"
  }, local.tags)
}

#-----------------------------------------------------------------------------------------------------------------------
# AKS Cluster
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "main" {
  name                              = local.cluster_name
  location                          = azurerm_resource_group.aks.location
  resource_group_name               = azurerm_resource_group.aks.name
  dns_prefix                        = local.cluster_name
  kubernetes_version                = var.kubernetes_version
  role_based_access_control_enabled = var.role_based_access_control_enabled
  automatic_upgrade_channel         = var.automatic_upgrade_channel
  sku_tier                          = var.sku_tier
  # checkov:skip=CKV_AZURE_6: This feature is in preview, we are using a public cluster for testing
  # api_server_authorized_ip_ranges   = [0.0.0.0/0]
  # checkov:skip=CKV_AZURE_115: We are using a public cluster for testing
  # private clusters are encouraged for production
  private_cluster_enabled = var.private_cluster_enabled
  disk_encryption_set_id  = azurerm_disk_encryption_set.main.id
  # checkov:skip=CKV_AZURE_116: This replaces the addon_profile
  azure_policy_enabled = var.azure_policy_enabled
  # checkov:skip=CKV_AZURE_141: We are setting this to false to avoid the creation of an AD
  local_account_disabled = var.local_account_disabled

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  default_node_pool {
    name                         = var.default_node_pool.name
    node_count                   = var.default_node_pool.node_count
    vm_size                      = var.default_node_pool.vm_size
    vnet_subnet_id               = coalesce(var.vnet_subnet_id, try(data.azurerm_subnet.private[0].id, null))
    orchestrator_version         = var.kubernetes_version
    only_critical_addons_enabled = var.default_node_pool.only_critical_addons_enabled

    # checkov:skip=CKV_AZURE_226: we are using the managed disk type to reduce costs
    os_disk_type            = var.default_node_pool.os_disk_type
    host_encryption_enabled = var.default_node_pool.host_encryption_enabled

    # checkov:skip=CKV_AZURE_168: This is set in the variable by default to 50
    max_pods                    = var.default_node_pool.max_pods
    temporary_name_for_rotation = "rotate"
  }

  auto_scaler_profile {
    balance_similar_node_groups      = var.auto_scaler_profile.balance_similar_node_groups
    max_graceful_termination_sec     = var.auto_scaler_profile.max_graceful_termination_sec
    scale_down_delay_after_add       = var.auto_scaler_profile.scale_down_delay_after_add
    scale_down_delay_after_delete    = var.auto_scaler_profile.scale_down_delay_after_delete
    scale_down_delay_after_failure   = var.auto_scaler_profile.scale_down_delay_after_failure
    scan_interval                    = var.auto_scaler_profile.scan_interval
    scale_down_unneeded              = var.auto_scaler_profile.scale_down_unneeded
    scale_down_unready               = var.auto_scaler_profile.scale_down_unready
    scale_down_utilization_threshold = var.auto_scaler_profile.scale_down_utilization_threshold
  }

  workload_autoscaler_profile {
    keda_enabled                    = var.workload_autoscaler_profile.keda_enabled
    vertical_pod_autoscaler_enabled = var.workload_autoscaler_profile.vertical_pod_autoscaler_enabled
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_logs.id
  }

  identity {
    type         = length(var.user_assigned_identity_ids) > 0 ? "UserAssigned" : "SystemAssigned"
    identity_ids = var.user_assigned_identity_ids
  }

  dynamic "kubelet_identity" {
    for_each = var.kubelet_user_assigned_identity_id != null ? [1] : []
    content {
      client_id                 = var.kubelet_client_id
      object_id                 = var.kubelet_object_id
      user_assigned_identity_id = var.kubelet_user_assigned_identity_id
    }
  }

  tags = merge({
    Name = local.cluster_name
  }, local.tags)
}

resource "azurerm_kubernetes_cluster_node_pool" "autoscaled" {
  count                 = var.autoscaled_node_pool.enabled ? 1 : 0
  name                  = var.autoscaled_node_pool.name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.autoscaled_node_pool.vm_size
  mode                  = var.autoscaled_node_pool.mode
  auto_scaling_enabled  = true
  min_count             = var.autoscaled_node_pool.min_count
  max_count             = var.autoscaled_node_pool.max_count
  vnet_subnet_id        = coalesce(var.vnet_subnet_id, try(data.azurerm_subnet.private[0].id, null))
  orchestrator_version  = var.kubernetes_version
  # checkov:skip=CKV_AZURE_226: We are using the managed disk type to reduce costs
  os_disk_type = var.autoscaled_node_pool.os_disk_type
  # checkov:skip=CKV_AZURE_168: This is set in the variable by default to 50
  max_pods                    = var.autoscaled_node_pool.max_pods
  host_encryption_enabled     = var.autoscaled_node_pool.host_encryption_enabled
  temporary_name_for_rotation = "rotate"

  tags = merge({
    Name = var.autoscaled_node_pool.name
  }, local.tags)
}

resource "local_file" "kube_config" {
  content  = azurerm_kubernetes_cluster.main.kube_config_raw
  filename = local.kubeconfig_path
}
