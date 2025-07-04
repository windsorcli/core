mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
      object_id = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/subnet-test"
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
}

# Tests a full configuration with all optional variables explicitly set,
# verifying that the module correctly applies all user-supplied values for node pools and feature flags.
run "full_configuration" {
  command = plan

  variables {
    context_id          = "test"
    name                = "windsor-aks"
    cluster_name        = "test-cluster"
    resource_group_name = "test-rg"
    kubernetes_version  = "1.32"
    user_assigned_identity_ids = [
      "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-identity-1",
      "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-identity-2"
    ]
    kubelet_client_id                 = "test-client-id"
    kubelet_object_id                 = "test-object-id"
    kubelet_user_assigned_identity_id = "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-identity-1"
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
    condition     = azurerm_kubernetes_cluster.main.identity[0].type == "UserAssigned"
    error_message = "Cluster should use user-assigned identity when IDs are provided"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.identity[0].identity_ids) == 2
    error_message = "Cluster should have 2 user-assigned identity IDs"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id == "test-client-id"
    error_message = "Kubelet client ID should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id == "test-object-id"
    error_message = "Kubelet object ID should match input"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.kubelet_identity[0].user_assigned_identity_id == "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-identity-1"
    error_message = "Kubelet user-assigned identity ID should match input"
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
