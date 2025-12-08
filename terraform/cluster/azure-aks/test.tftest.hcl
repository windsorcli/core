mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
      object_id = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      subnets             = ["private-1-test", "private-2-test", "private-3-test", "public-1-test", "public-2-test", "isolated-1-test", "isolated-2-test"]
      resource_group_name = "example-resource-group"
      name                = "vnet-test"
      id                  = "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.Network/virtualNetworks/vnet-test"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      name                 = "private-1-test"
      resource_group_name  = "example-resource-group"
      virtual_network_name = "vnet-test"
      address_prefixes     = ["10.0.0.0/24"]
      id                   = "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/subnet-test"
    }
  }
}

# Verifies that the module creates an AKS cluster with minimal configuration,
# ensuring that all default values are correctly applied and only required variables are set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id         = "test"
    name               = "windsor-aks"
    kubernetes_version = "1.32"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.name == "windsor-aks-test"
    error_message = "Cluster name should default to 'windsor-aks-test' when cluster_name is omitted"
  }

  assert {
    condition     = azurerm_resource_group.aks.name == "windsor-aks-test"
    error_message = "Resource group name should default to 'windsor-aks-test' when resource_group_name is omitted"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].name == "system"
    error_message = "Default node pool should use 'system' name"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].vm_size == "Standard_D2s_v3"
    error_message = "Default node pool should use Standard_D2s_v3 VM size"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].node_count == 1
    error_message = "Default node pool should have 1 node"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.role_based_access_control_enabled == true
    error_message = "RBAC should be enabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.private_cluster_enabled == false
    error_message = "Private cluster should be disabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.azure_policy_enabled == true
    error_message = "Azure policy should be enabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.local_account_disabled == false
    error_message = "Local accounts should be enabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.identity[0].type == "SystemAssigned"
    error_message = "Cluster should use system-assigned identity by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.oidc_issuer_enabled == true
    error_message = "OIDC issuer should be enabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.workload_identity_enabled == true
    error_message = "Workload Identity should be enabled by default"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/read")
    error_message = "Snapshot permissions should be included when enable_volume_snapshots is true (default)"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/write")
    error_message = "Snapshot write permissions should be included when enable_volume_snapshots is true (default)"
  }
}

# Tests a full configuration with all optional variables explicitly set,
# verifying that the module correctly applies all user-supplied values for node pools and feature flags.
run "full_configuration" {
  command = plan

  variables {
    context_id                = "test"
    name                      = "windsor-aks"
    cluster_name              = "test-cluster"
    resource_group_name       = "test-rg"
    kubernetes_version        = "1.32"
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
    default_node_pool = {
      name                         = "system"
      vm_size                      = "Standard_D2s_v3"
      os_disk_type                 = "Managed"
      max_pods                     = 30
      host_encryption_enabled      = true
      min_count                    = 1
      max_count                    = 3
      node_count                   = 1
      only_critical_addons_enabled = false
    }
    autoscaled_node_pool = {
      enabled                 = true
      name                    = "autoscaled"
      vm_size                 = "Standard_D2s_v3"
      mode                    = "User"
      os_disk_type            = "Managed"
      max_pods                = 30
      host_encryption_enabled = true
      min_count               = 1
      max_count               = 3
    }
    role_based_access_control_enabled = true
    private_cluster_enabled           = false
    azure_policy_enabled              = true
    local_account_disabled            = false
    enable_volume_snapshots            = true
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.name == "test-cluster"
    error_message = "Cluster name should match input"
  }

  assert {
    condition     = azurerm_resource_group.aks.name == "test-rg"
    error_message = "Resource group name should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].name == "system"
    error_message = "Default node pool name should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].vm_size == "Standard_D2s_v3"
    error_message = "Default node pool VM size should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].max_pods == 30
    error_message = "Default node pool max pods should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.default_node_pool[0].host_encryption_enabled == true
    error_message = "Default node pool host encryption should be enabled"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.autoscaled) == 1
    error_message = "Autoscaled node pool should be created when enabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.autoscaled[0].name == "autoscaled"
    error_message = "Autoscaled node pool name should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.autoscaled[0].vm_size == "Standard_D2s_v3"
    error_message = "Autoscaled node pool VM size should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.autoscaled[0].max_pods == 30
    error_message = "Autoscaled node pool max pods should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.autoscaled[0].host_encryption_enabled == true
    error_message = "Autoscaled node pool host encryption should be enabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.role_based_access_control_enabled == true
    error_message = "RBAC should be enabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.private_cluster_enabled == false
    error_message = "Private cluster should be disabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.azure_policy_enabled == true
    error_message = "Azure policy should be enabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.local_account_disabled == false
    error_message = "Local accounts should be enabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.identity[0].type == "SystemAssigned"
    error_message = "Cluster should use system-assigned identity"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.oidc_issuer_enabled == true
    error_message = "OIDC issuer should be enabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.workload_identity_enabled == true
    error_message = "Workload Identity should be enabled"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/read")
    error_message = "Snapshot permissions should be included when enable_volume_snapshots is true"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/write")
    error_message = "Snapshot write permissions should be included when enable_volume_snapshots is true"
  }
}

# Tests the private cluster configuration, ensuring that enabling the private_cluster_enabled
# variable results in a private AKS cluster as expected.
run "private_cluster" {
  command = plan

  variables {
    context_id              = "test"
    name                    = "windsor-aks"
    cluster_name            = "test-cluster"
    private_cluster_enabled = true
    kubernetes_version      = "1.32"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.private_cluster_enabled == true
    error_message = "Private cluster should be enabled"
  }
}

# Verifies that a kubeconfig file is generated,
# ensuring proper cluster access configuration.
run "config_file_created" {
  command = plan

  variables {
    context_id   = "test"
    name         = "windsor-aks"
    cluster_name = "test-cluster"
    context_path = "/tmp"
  }

  assert {
    condition     = length(local_file.kube_config) >= 1
    error_message = "Kubeconfig file should be generated when context path is provided"
  }
}

run "network_configuration" {
  command = plan

  variables {
    context_id     = "test"
    service_cidr   = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].service_cidr == "10.0.0.0/16"
    error_message = "Service CIDR should match input value"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].dns_service_ip == "10.0.0.10"
    error_message = "DNS service IP should match input value"
  }
}

run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
    var.kubernetes_version,
  ]
  variables {
    context_id         = "test"
    kubernetes_version = "v1.32"
  }
}

# Tests that when enable_volume_snapshots is false, snapshot permissions are not included in the role definition.
# This verifies the conditional logic that excludes snapshot operations when volume snapshots are disabled.
run "volume_snapshots_disabled" {
  command = plan

  variables {
    context_id             = "test"
    name                   = "windsor-aks"
    kubernetes_version     = "1.32"
    enable_volume_snapshots = false
  }

  assert {
    condition     = !contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/read")
    error_message = "Snapshot read permissions should not be included when enable_volume_snapshots is false"
  }

  assert {
    condition     = !contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/write")
    error_message = "Snapshot write permissions should not be included when enable_volume_snapshots is false"
  }

  assert {
    condition     = !contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/delete")
    error_message = "Snapshot delete permissions should not be included when enable_volume_snapshots is false"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/disks/read")
    error_message = "Core disk permissions should still be included when enable_volume_snapshots is false"
  }
}
