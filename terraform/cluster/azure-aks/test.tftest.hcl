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
}

# Stand-in subnet IDs every run block feeds into var.private_subnet_ids via
# the shared `variables` block below. Three entries lets the role-assignment
# for_each fan out to >1 scope and exercises the default/autoscaled pool's
# first/last picks landing on different subnets.
variables {
  private_subnet_ids = [
    "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/private-1-test",
    "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/private-2-test",
    "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/example-resource-group/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/private-3-test",
  ]
}


# Verifies that the module creates an AKS cluster with minimal configuration,
# ensuring that all default values are correctly applied and only required variables are set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id         = "test"
    name               = "windsor-aks"
    kubernetes_version = "1.34"
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

  assert {
    condition     = azurerm_kubernetes_cluster.main.oidc_issuer_enabled == true
    error_message = "OIDC issuer should be enabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.workload_identity_enabled == true
    error_message = "Workload Identity should be enabled by default"
  }

  assert {
    condition     = length(azurerm_key_vault_key.key_vault_key) == 1
    error_message = "Key Vault key should be created when disk_encryption_enabled is true and key_vault_key_id is null (default)"
  }

  assert {
    condition     = length(azurerm_disk_encryption_set.main) == 1
    error_message = "Disk encryption set should be created when disk_encryption_enabled is true (default)"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].outbound_type == "userAssignedNATGateway"
    error_message = "Default outbound type should be 'userAssignedNATGateway'"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].network_plugin_mode == "overlay"
    error_message = "Network plugin mode should be 'overlay'"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].network_data_plane == "cilium"
    error_message = "Network data plane should be 'cilium'"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/read")
    error_message = "Snapshot permissions should be included when enable_volume_snapshots is true (default)"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/write")
    error_message = "Snapshot write permissions should be included when enable_volume_snapshots is true (default)"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.image_cleaner_enabled == true
    error_message = "Image Cleaner should be enabled by default"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.image_cleaner_interval_hours == 48
    error_message = "Image Cleaner interval should default to 48 hours"
  }

  assert {
    condition     = length(null_resource.convert_kubeconfig) == 0
    error_message = "convert_kubeconfig resource should not be created when kubelogin_mode is empty (default)"
  }

  assert {
    condition     = length(azurerm_role_assignment.subnet_network_contributor_cp) == 3
    error_message = "Network Contributor role should be assigned once per private subnet (3 in this run's input list)"
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
    kubernetes_version        = "1.34"
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
      availability_zones           = ["1", "2", "3"]
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
      availability_zones      = ["1", "2"]
    }
    role_based_access_control_enabled = true
    private_cluster_enabled           = false
    azure_policy_enabled              = true
    local_account_disabled            = false
    disk_encryption_enabled           = true
    key_vault_key_id                  = null
    outbound_type                     = "loadBalancer"
    authorized_ip_ranges              = ["10.0.0.0/8"]
    admin_object_ids                  = ["55555555-5555-5555-5555-555555555555"]
    enable_volume_snapshots           = true
    image_cleaner_enabled             = true
    image_cleaner_interval_hours      = 24
    context_path                      = "/tmp"
    kubelogin_mode                    = "azurecli"
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
    error_message = "Local accounts should be disabled when explicitly set to false"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.identity[0].type == "SystemAssigned"
    error_message = "Cluster should use system-assigned identity"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.main.default_node_pool[0].zones) == 3 && contains(azurerm_kubernetes_cluster.main.default_node_pool[0].zones, "1") && contains(azurerm_kubernetes_cluster.main.default_node_pool[0].zones, "2") && contains(azurerm_kubernetes_cluster.main.default_node_pool[0].zones, "3")
    error_message = "Default node pool zones should match input value"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.autoscaled[0].zones) == 2 && contains(azurerm_kubernetes_cluster_node_pool.autoscaled[0].zones, "1") && contains(azurerm_kubernetes_cluster_node_pool.autoscaled[0].zones, "2")
    error_message = "Autoscaled node pool zones should match input value"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].outbound_type == "loadBalancer"
    error_message = "Outbound type should match input value"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].network_plugin_mode == "overlay"
    error_message = "Network plugin mode should be 'overlay'"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.network_profile[0].network_data_plane == "cilium"
    error_message = "Network data plane should be 'cilium'"
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
    condition     = length(azurerm_key_vault_key.key_vault_key) == 1
    error_message = "Key Vault key should be created when disk_encryption_enabled is true and key_vault_key_id is null"
  }

  assert {
    condition     = length(azurerm_disk_encryption_set.main) == 1
    error_message = "Disk encryption set should be created when disk_encryption_enabled is true"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/read")
    error_message = "Snapshot permissions should be included when enable_volume_snapshots is true"
  }

  assert {
    condition     = contains(azurerm_role_definition.aks_kubelet_vmss_disk_manager.permissions[0].actions, "Microsoft.Compute/snapshots/write")
    error_message = "Snapshot write permissions should be included when enable_volume_snapshots is true"
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

  assert {
    condition     = azurerm_kubernetes_cluster.main.image_cleaner_enabled == true
    error_message = "Image Cleaner should be enabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.main.image_cleaner_interval_hours == 24
    error_message = "Image Cleaner interval should match input value"
  }

  assert {
    condition     = length(null_resource.convert_kubeconfig) == 1
    error_message = "convert_kubeconfig resource should be created when kubelogin_mode is set"
  }

  assert {
    condition     = null_resource.convert_kubeconfig[0].triggers.login_mode == "azurecli"
    error_message = "convert_kubeconfig trigger should include login_mode set to azurecli"
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
    kubernetes_version      = "1.34"
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
    condition     = length(local_sensitive_file.kubeconfig) >= 1
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
    context_id           = "test"
    name                 = "windsor-aks"
    cluster_name         = "test-cluster"
    kubernetes_version   = "1.34"
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
    context_id             = "test"
    name                   = "windsor-aks"
    cluster_name           = "test-cluster"
    kubernetes_version     = "1.34"
    local_account_disabled = true
    admin_object_ids       = ["33333333-3333-3333-3333-333333333333", "44444444-4444-4444-4444-444444444444"]
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
    var.outbound_type,
  ]
  variables {
    context_id         = "test"
    kubernetes_version = "v1.34"
    outbound_type      = "invalid"
  }
}

# Tests that when key_vault_key_id is provided, no key is created and the provided key ID is used.
# This verifies the conditional logic that skips key creation when an external key is specified.
run "disk_encryption_with_provided_key" {
  command = plan

  variables {
    context_id              = "test"
    name                    = "windsor-aks"
    kubernetes_version      = "1.34"
    disk_encryption_enabled = true
    key_vault_key_id        = "https://test-kv.vault.azure.net/keys/test-key/abc123"
  }

  assert {
    condition     = length(azurerm_key_vault_key.key_vault_key) == 0
    error_message = "Key Vault key should not be created when key_vault_key_id is provided"
  }

  assert {
    condition     = length(azurerm_disk_encryption_set.main) == 1
    error_message = "Disk encryption set should be created when disk_encryption_enabled is true"
  }

  assert {
    condition     = azurerm_disk_encryption_set.main[0].key_vault_key_id == "https://test-kv.vault.azure.net/keys/test-key/abc123"
    error_message = "Disk encryption set should use the provided key_vault_key_id when specified"
  }
}

# Tests that the cert-manager and external-dns Workload Identity blocks are
# off by default for cert-manager and on by default for external-dns. The
# default settings mirror the AWS cluster module's defaults — clusters that
# don't ask for ACME shouldn't pay for an unused UAMI, but external-dns is
# baseline-on so any cluster can publish hostnames once a zone is wired in.
run "workload_identity_defaults" {
  command = plan

  variables {
    context_id         = "test"
    name               = "windsor-aks"
    kubernetes_version = "1.34"
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.cert_manager) == 0
    error_message = "cert-manager UAMI must not be provisioned by default."
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.cert_manager) == 0
    error_message = "cert-manager federated credential must not be provisioned by default."
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.external_dns) == 1
    error_message = "external-dns UAMI must be provisioned by default (matches the AWS create_external_dns_role default)."
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.external_dns) == 1
    error_message = "external-dns federated credential must be provisioned by default."
  }

  assert {
    condition     = azurerm_federated_identity_credential.external_dns[0].subject == "system:serviceaccount:system-dns:external-dns"
    error_message = "Default federated credential subject must target the external-dns SA in system-dns."
  }
}

# Tests cert-manager Workload Identity provisioning end-to-end: the UAMI is
# created, the federated credential subject targets the cert-manager SA in
# system-pki, and the role assignment is scoped to each supplied zone ID.
# The fan-out via for_each over zone IDs lets the operator hand cert-manager
# multiple zones (e.g. apex + delegated subdomain) with one var.
run "cert_manager_workload_identity" {
  command = plan

  variables {
    context_id                   = "test"
    name                         = "windsor-aks"
    kubernetes_version           = "1.34"
    create_cert_manager_identity = true
    cert_manager_dns_zone_ids = [
      "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/rg-dns-test/providers/Microsoft.Network/dnszones/example.com",
      "/subscriptions/12345678-1234-9876-4563-123456789012/resourceGroups/rg-dns-test/providers/Microsoft.Network/dnszones/example.org"
    ]
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.cert_manager) == 1
    error_message = "cert-manager UAMI should be provisioned when create_cert_manager_identity is true."
  }

  assert {
    condition     = azurerm_user_assigned_identity.cert_manager[0].name == "windsor-aks-test-cert-manager"
    error_message = "cert-manager UAMI name should follow <cluster_name>-cert-manager."
  }

  assert {
    condition     = length(azurerm_role_assignment.cert_manager_dns) == 2
    error_message = "One DNS Zone Contributor assignment per zone ID."
  }

  assert {
    condition     = azurerm_federated_identity_credential.cert_manager[0].subject == "system:serviceaccount:system-pki:cert-manager"
    error_message = "Federated credential subject must follow system:serviceaccount:<ns>:<sa> using the cert_manager_namespace + cert_manager_service_account defaults."
  }

  assert {
    condition     = contains(azurerm_federated_identity_credential.cert_manager[0].audience, "api://AzureADTokenExchange")
    error_message = "Audience must include api://AzureADTokenExchange — Azure AD rejects the token exchange otherwise."
  }
}

# Tests external-dns can be turned off explicitly — important for clusters
# that intentionally publish DNS records via another mechanism (Azure
# Application Routing add-on, manual records, etc.).
run "external_dns_identity_disabled" {
  command = plan

  variables {
    context_id                   = "test"
    name                         = "windsor-aks"
    kubernetes_version           = "1.34"
    create_external_dns_identity = false
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.external_dns) == 0
    error_message = "external-dns UAMI should not be provisioned when create_external_dns_identity is false."
  }

  assert {
    condition     = length(azurerm_role_assignment.external_dns_zones) == 0
    error_message = "external-dns role assignments should not be provisioned when create_external_dns_identity is false."
  }
}

# Tests that when enable_volume_snapshots is false, snapshot permissions are not included in the role definition.
# This verifies the conditional logic that excludes snapshot operations when volume snapshots are disabled.
run "volume_snapshots_disabled" {
  command = plan

  variables {
    context_id              = "test"
    name                    = "windsor-aks"
    kubernetes_version      = "1.34"
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
