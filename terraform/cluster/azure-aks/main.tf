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
  location = "eastus"
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
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id = data.azurerm_subnet.private.id

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
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

resource "local_file" "kube_config" {
  content  = azurerm_kubernetes_cluster.main.kube_config_raw
  filename = local.kubeconfig_path
}
