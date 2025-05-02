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
  features {}
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  kubeconfig_path = "${var.context_path}/.kube/config"
}

#-----------------------------------------------------------------------------------------------------------------------
# AKS Cluster
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "aks" {
  name     = "${var.prefix}-aks-rg"
  location = var.region
}

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

  default_node_pool {
    name                         = "system"
    node_count                   = 1
    vm_size                      = "Standard_D2s_v3"
    vnet_subnet_id               = data.azurerm_subnet.private.id
    orchestrator_version         = var.kubernetes_version
    only_critical_addons_enabled = true
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
  min_count             = 1
  max_count             = 3
  vnet_subnet_id        = data.azurerm_subnet.private.id
  orchestrator_version  = var.kubernetes_version
  node_labels = {
    role = "app"
  }
}

resource "local_file" "kube_config" {
  content  = azurerm_kubernetes_cluster.main.kube_config_raw
  filename = local.kubeconfig_path
}
