mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
      object_id = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_data "azurerm_subscription" {
    defaults = {
      subscription_id = "12345678-1234-9876-4563-123456789012"
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
    condition     = azurerm_kubernetes_cluster.main.local_account_disabled == true
    error_message = "Local accounts should be disabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.identity[0].type == "SystemAssigned"
    error_message = "Cluster should use system-assigned identity by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "Azure RBAC should be enabled by default"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].admin_group_object_ids) == 0
    error_message = "Admin group object IDs should be empty by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.api_server_access_profile[0].authorized_ip_ranges == null
    error_message = "Authorized IP ranges should be null by default (allowing all)"
  }

  assert {
    condition     = length(azurerm_role_assignment.aks_rbac_admin) == 1
    error_message = "Role assignment should be created for the deployer identity by default"
  }

  assert {
    condition     = azurerm_role_assignment.aks_rbac_admin["22222222-2222-2222-2222-222222222222"].role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin"
    error_message = "Role assignment should use 'Azure Kubernetes Service RBAC Cluster Admin' role"
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
    authorized_ip_ranges              = ["10.0.0.0/8"]
    admin_object_ids                  = ["55555555-5555-5555-5555-555555555555"]
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

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.api_server_access_profile[0].authorized_ip_ranges) == 1
    error_message = "Authorized IP ranges should contain 1 entry"
  }

  assert {
    condition     = contains(azurerm_kubernetes_cluster.main.api_server_access_profile[0].authorized_ip_ranges, "10.0.0.0/8")
    error_message = "Authorized IP ranges should include 10.0.0.0/8"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "Azure RBAC should be enabled"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].admin_group_object_ids) == 1
    error_message = "Admin group object IDs should contain 1 entry"
  }

  assert {
    condition     = contains(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].admin_group_object_ids, "55555555-5555-5555-5555-555555555555")
    error_message = "Admin group object IDs should include the specified object ID"
  }

  assert {
    condition     = length(azurerm_role_assignment.aks_rbac_admin) == 2
    error_message = "Role assignments should be created for deployer plus 1 admin object ID (2 total)"
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

# Tests the authorized IP ranges configuration, ensuring that setting authorized_ip_ranges
# results in the API server access profile being configured with the specified IP ranges.
run "authorized_ip_ranges" {
  command = plan

  variables {
    context_id          = "test"
    name                = "windsor-aks"
    cluster_name        = "test-cluster"
    kubernetes_version  = "1.32"
    authorized_ip_ranges = ["10.0.0.0/8", "192.168.0.0/16"]
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.api_server_access_profile[0].authorized_ip_ranges) == 2
    error_message = "Authorized IP ranges should contain 2 entries"
  }

  assert {
    condition     = contains(azurerm_kubernetes_cluster.main.api_server_access_profile[0].authorized_ip_ranges, "10.0.0.0/8")
    error_message = "Authorized IP ranges should include 10.0.0.0/8"
  }

  assert {
    condition     = contains(azurerm_kubernetes_cluster.main.api_server_access_profile[0].authorized_ip_ranges, "192.168.0.0/16")
    error_message = "Authorized IP ranges should include 192.168.0.0/16"
  }
}

# Tests the Azure RBAC configuration with admin object IDs, ensuring that the
# azure_active_directory_role_based_access_control block is configured correctly and
# role assignments are created for all specified admin object IDs plus the deployer.
run "azure_rbac_with_admin_object_ids" {
  command = plan

  variables {
    context_id          = "test"
    name                = "windsor-aks"
    cluster_name        = "test-cluster"
    kubernetes_version  = "1.32"
    local_account_disabled = true
    admin_object_ids    = ["33333333-3333-3333-3333-333333333333", "44444444-4444-4444-4444-444444444444"]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "Azure RBAC should be enabled"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].admin_group_object_ids) == 2
    error_message = "Admin group object IDs should contain 2 entries"
  }

  assert {
    condition     = contains(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].admin_group_object_ids, "33333333-3333-3333-3333-333333333333")
    error_message = "Admin group object IDs should include the first specified object ID"
  }

  assert {
    condition     = contains(azurerm_kubernetes_cluster.main.azure_active_directory_role_based_access_control[0].admin_group_object_ids, "44444444-4444-4444-4444-444444444444")
    error_message = "Admin group object IDs should include the second specified object ID"
  }

  assert {
    condition     = length(azurerm_role_assignment.aks_rbac_admin) == 3
    error_message = "Role assignments should be created for deployer plus 2 admin object IDs (3 total)"
  }

  assert {
    condition     = azurerm_role_assignment.aks_rbac_admin["22222222-2222-2222-2222-222222222222"].role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin"
    error_message = "Role assignment for deployer should use 'Azure Kubernetes Service RBAC Cluster Admin' role"
  }

  assert {
    condition     = azurerm_role_assignment.aks_rbac_admin["33333333-3333-3333-3333-333333333333"].role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin"
    error_message = "Role assignment for first admin should use 'Azure Kubernetes Service RBAC Cluster Admin' role"
  }

  assert {
    condition     = azurerm_role_assignment.aks_rbac_admin["44444444-4444-4444-4444-444444444444"].role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin"
    error_message = "Role assignment for second admin should use 'Azure Kubernetes Service RBAC Cluster Admin' role"
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
