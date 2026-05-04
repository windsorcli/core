#---------------------------------------------------------------------------------------------------
# Versions
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.70.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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

data "azurerm_subscription" "current" {}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  kubeconfig_path          = "${var.context_path}/.kube/config"
  rg_name                  = var.resource_group_name == null ? "${var.name}-${var.context_id}" : var.resource_group_name
  cluster_name             = var.cluster_name == null ? "${var.name}-${var.context_id}" : var.cluster_name
  node_resource_group_name = split("/", azurerm_kubernetes_cluster.main.node_resource_group_id)[4]
  node_pool_names = concat(
    [var.default_node_pool.name],
    var.autoscaled_node_pool.enabled ? [var.autoscaled_node_pool.name] : []
  )
  # Safely access kubelet identity (may not be available during plan in tests)
  kubelet_object_id      = try(azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id, "00000000-0000-0000-0000-000000000000")
  disk_encryption_key_id = var.key_vault_key_id != null ? var.key_vault_key_id : try(azurerm_key_vault_key.key_vault_key[0].id, null)
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
  enabled_for_disk_encryption = var.disk_encryption_enabled
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
  count = var.disk_encryption_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.key_vault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_disk_encryption_set.main[0].identity.0.principal_id

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

# Moved block to handle transition from single instance to count-based resource
moved {
  from = azurerm_key_vault_access_policy.key_vault_access_policy_disk
  to   = azurerm_key_vault_access_policy.key_vault_access_policy_disk[0]
}

resource "time_static" "expiry" {}

resource "azurerm_key_vault_key" "key_vault_key" {
  count = var.disk_encryption_enabled && var.key_vault_key_id == null ? 1 : 0

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

# Moved block to handle transition from single instance to count-based resource
moved {
  from = azurerm_key_vault_key.key_vault_key
  to   = azurerm_key_vault_key.key_vault_key[0]
}

resource "azurerm_disk_encryption_set" "main" {
  count = var.disk_encryption_enabled ? 1 : 0

  name                = "${var.name}-${var.context_id}-${random_string.key.result}"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  key_vault_key_id    = local.disk_encryption_key_id

  identity {
    type = "SystemAssigned"
  }
}

# Moved block to handle transition from single instance to count-based resource
moved {
  from = azurerm_disk_encryption_set.main
  to   = azurerm_disk_encryption_set.main[0]
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

resource "azurerm_monitor_diagnostic_setting" "aks_cluster" {
  name                       = "${var.name}-${var.context_id}-aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_logs.id

  dynamic "enabled_log" {
    for_each = var.diagnostic_log_categories
    content {
      category = enabled_log.value

      dynamic "retention_policy" {
        for_each = var.diagnostic_log_retention_days != null ? [1] : []
        content {
          enabled = true
          days    = var.diagnostic_log_retention_days
        }
      }
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Data Collection Rule (DCR)
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  count               = var.container_insights_enabled ? 1 : 0
  name                = "${var.name}-${var.context_id}-dcr"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.aks_logs.id
      name                  = "ciworkspace"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      streams        = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
      extension_name = "ContainerInsights"
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m",
          namespaceFilteringMode = "Off",
          enableContainerLogV2   = true
        }
      })
      name = "ContainerInsightsExtension"
    }
  }

  description = "DCR for Azure Monitor Container Insights"
  tags        = local.tags
}

resource "azurerm_monitor_data_collection_rule_association" "aks_dcr" {
  count                   = var.container_insights_enabled ? 1 : 0
  name                    = "${var.name}-${var.context_id}-dcr-assoc"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights[0].id
  description             = "Association of DCR to AKS Cluster"
}

#-----------------------------------------------------------------------------------------------------------------------
# AKS Cluster
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = local.cluster_name
  # checkov:skip=CKV_AZURE_339: Kubernetes version is populated from the cloud provider's stable version via Renovate.
  # checkov:skip=CKV_AZURE_4: Diagnostic settings are configured via azurerm_monitor_diagnostic_setting.aks_cluster resource
  kubernetes_version                = var.kubernetes_version
  role_based_access_control_enabled = var.role_based_access_control_enabled
  automatic_upgrade_channel         = var.automatic_upgrade_channel
  sku_tier                          = var.sku_tier

  # checkov:skip=CKV_AZURE_6: We allow user to restrict IPs or default to open (null)
  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  # checkov:skip=CKV_AZURE_115: We are using a public cluster for testing
  private_cluster_enabled = var.private_cluster_enabled
  disk_encryption_set_id  = var.disk_encryption_enabled ? azurerm_disk_encryption_set.main[0].id : null
  # checkov:skip=CKV_AZURE_116: This replaces the addon_profile
  azure_policy_enabled = var.azure_policy_enabled
  # checkov:skip=CKV_AZURE_141: We are setting this to false to avoid the creation of an AD
  local_account_disabled = var.local_account_disabled

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_object_ids
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  default_node_pool {
    name                         = var.default_node_pool.name
    node_count                   = var.default_node_pool.node_count
    vm_size                      = var.default_node_pool.vm_size
    vnet_subnet_id               = var.private_subnet_ids[0]
    orchestrator_version         = var.kubernetes_version
    only_critical_addons_enabled = var.default_node_pool.only_critical_addons_enabled
    zones                        = var.default_node_pool.availability_zones

    # checkov:skip=CKV_AZURE_226: we are using the managed disk type to reduce costs
    os_disk_type            = var.default_node_pool.os_disk_type
    host_encryption_enabled = var.default_node_pool.host_encryption_enabled

    # checkov:skip=CKV_AZURE_168: This is set in the variable by default to 50
    max_pods                    = var.default_node_pool.max_pods
    temporary_name_for_rotation = "rotate"

    dynamic "upgrade_settings" {
      for_each = var.default_node_pool.upgrade_settings != null ? [var.default_node_pool.upgrade_settings] : []
      content {
        drain_timeout_in_minutes      = upgrade_settings.value.drain_timeout_in_minutes
        max_surge                     = upgrade_settings.value.max_surge
        node_soak_duration_in_minutes = upgrade_settings.value.node_soak_duration_in_minutes
      }
    }
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

  # Emit the block only when at least one autoscaler is enabled. Azure's GET
  # response omits this block entirely when both knobs are at their default
  # (false), so an unconditional block here produces "+ workload_autoscaler_profile"
  # drift on every plan against an unchanged cluster.
  dynamic "workload_autoscaler_profile" {
    for_each = (var.workload_autoscaler_profile.keda_enabled || var.workload_autoscaler_profile.vertical_pod_autoscaler_enabled) ? [1] : []
    content {
      keda_enabled                    = var.workload_autoscaler_profile.keda_enabled
      vertical_pod_autoscaler_enabled = var.workload_autoscaler_profile.vertical_pod_autoscaler_enabled
    }
  }

  oidc_issuer_enabled          = var.oidc_issuer_enabled
  workload_identity_enabled    = var.workload_identity_enabled
  image_cleaner_enabled        = var.image_cleaner_enabled
  image_cleaner_interval_hours = var.image_cleaner_interval_hours

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    outbound_type       = var.outbound_type
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  # Use system-assigned managed identity (Microsoft default and best practice)
  # AKS automatically creates Contributor role on node RG for control plane
  # AKS automatically creates Virtual Machine Contributor role on node RG for kubelet
  identity {
    type = "SystemAssigned"
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
  zones                 = var.autoscaled_node_pool.availability_zones
  vnet_subnet_id        = var.private_subnet_ids[length(var.private_subnet_ids) - 1]
  orchestrator_version  = var.kubernetes_version
  # checkov:skip=CKV_AZURE_226: We are using the managed disk type to reduce costs
  os_disk_type = var.autoscaled_node_pool.os_disk_type
  # checkov:skip=CKV_AZURE_168: This is set in the variable by default to 50
  max_pods                    = var.autoscaled_node_pool.max_pods
  host_encryption_enabled     = var.autoscaled_node_pool.host_encryption_enabled
  temporary_name_for_rotation = "rotate"

  dynamic "upgrade_settings" {
    for_each = try(var.autoscaled_node_pool.upgrade_settings, null) != null ? [var.autoscaled_node_pool.upgrade_settings] : []
    content {
      drain_timeout_in_minutes      = upgrade_settings.value.drain_timeout_in_minutes
      max_surge                     = upgrade_settings.value.max_surge
      node_soak_duration_in_minutes = upgrade_settings.value.node_soak_duration_in_minutes
    }
  }

  tags = merge({
    Name = var.autoscaled_node_pool.name
  }, local.tags)
}

#-----------------------------------------------------------------------------------------------------------------------
# Portable User Pools (var.pools)
#-----------------------------------------------------------------------------------------------------------------------

# Resolve the portable pool shape into Azure-specific fields:
#  - vm_size: AKS pools take a single SKU, not a list. Pick the first item from
#    the operator's instance_types override; fall back to class_instance_types
#    so the operator can declare a pool with class=general and no explicit SKU.
#  - priority: lifecycle 'spot' → AKS Spot pool (delete-on-eviction).
#  - taints: AKS expects the API's "key=value:Effect" string form (PascalCase
#    effect: NoSchedule / NoExecute / PreferNoSchedule). Operator-supplied
#    effect strings pass through; cross-platform configs use the AKS form when
#    targeting Azure.
#  - labels: standard kubernetes label map, with windsorcli.dev/pool[-class]
#    tags appended so node-affinity rules can pin workloads by pool name or class.
locals {
  pools_resolved = {
    for name, p in var.pools : name => {
      vm_size = (p.instance_types != null && length(p.instance_types) > 0
        ? p.instance_types[0]
      : lookup(var.class_instance_types, p.class, [""])[0])
      priority        = p.lifecycle == "spot" ? "Spot" : "Regular"
      eviction_policy = p.lifecycle == "spot" ? "Delete" : null
      node_count      = p.count
      os_disk_size_gb = coalesce(p.root_disk_size, 64)
      labels = merge(
        p.labels,
        {
          "windsorcli.dev/pool"       = name
          "windsorcli.dev/pool-class" = p.class
        }
      )
      taints = [for t in p.taints : "${t.key}=${t.value != null ? t.value : ""}:${t.effect}"]
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "pools" {
  for_each              = local.pools_resolved
  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  mode                  = "User"
  node_count            = each.value.node_count
  os_disk_size_gb       = each.value.os_disk_size_gb
  vnet_subnet_id        = var.private_subnet_ids[length(var.private_subnet_ids) - 1]
  orchestrator_version  = var.kubernetes_version
  priority              = each.value.priority
  eviction_policy       = each.value.eviction_policy
  node_labels           = each.value.labels
  node_taints           = each.value.taints
  # Encrypt temp disks / VM cache for parity with the default and autoscaled
  # pools (CKV_AZURE_227).
  host_encryption_enabled = true
  # 50 satisfies CKV_AZURE_168 (>=50) directly without needing a suppression.
  # The default and autoscaled pools still use 48 with skip comments; left
  # alone here to keep this change scoped to the new resource.
  max_pods = 50

  tags = merge({
    Name = each.key
  }, local.tags)
}

# Assign Network Contributor role on each private subnet to the control plane identity
# (required for custom VNet). Azure CLI auto-assigns this; Terraform requires it explicitly.
# Scoped per-subnet so every subnet a node pool may attach to is covered, not just the first.
# Reference: https://learn.microsoft.com/azure/aks/configure-kubenet
resource "azurerm_role_assignment" "subnet_network_contributor_cp" {
  for_each             = toset(var.private_subnet_ids)
  scope                = each.value
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# AKS automatically creates Virtual Machine Contributor role assignment on node resource group for the kubelet identity.
# However, disk attachment operations require additional permissions beyond Virtual Machine Contributor.
# Create a custom role with minimal permissions for VMSS disk operations.
resource "azurerm_role_definition" "aks_kubelet_vmss_disk_manager" {
  name        = "AKS Kubelet VMSS Disk Manager - ${var.context_id}"
  scope       = azurerm_kubernetes_cluster.main.node_resource_group_id
  description = "Minimal permissions for AKS kubelet identity to manage VMSS disk attachments"

  permissions {
    actions = concat(
      [
        # VMSS virtual machine operations for disk attachment (REQUIRED)
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
        "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/write",
        # Core disk operations (REQUIRED for basic disk attachment)
        "Microsoft.Compute/disks/read",
        "Microsoft.Compute/disks/write",
        "Microsoft.Compute/disks/delete",
        "Microsoft.Compute/disks/beginGetAccess/action",
        "Microsoft.Compute/disks/endGetAccess/action",
        # Location/operation queries (may be needed for operation status checks)
        "Microsoft.Compute/locations/DiskOperations/read",
        "Microsoft.Compute/locations/vmSizes/read",
        "Microsoft.Compute/locations/operations/read"
      ],
      var.enable_volume_snapshots ? [
        # Snapshot operations (only included if volume snapshots are enabled)
        "Microsoft.Compute/snapshots/read",
        "Microsoft.Compute/snapshots/write",
        "Microsoft.Compute/snapshots/delete"
      ] : []
    )
    not_actions = []
  }

  assignable_scopes = [
    azurerm_kubernetes_cluster.main.node_resource_group_id
  ]
}

resource "azurerm_role_assignment" "kubelet_vmss_disk_manager" {
  scope              = azurerm_kubernetes_cluster.main.node_resource_group_id
  role_definition_id = azurerm_role_definition.aks_kubelet_vmss_disk_manager.role_definition_resource_id
  principal_id       = local.kubelet_object_id
}

# Assign Reader role on the disk encryption set to the control plane identity.
# Required when using Customer-Managed Keys (CMK) for disk encryption.
resource "azurerm_role_assignment" "cp_disk_encryption_set_reader" {
  count = var.disk_encryption_enabled ? 1 : 0

  scope                = azurerm_disk_encryption_set.main[0].id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# Assign Reader role on the disk encryption set to the kubelet identity.
# Required when using Customer-Managed Keys (CMK) for disk encryption.
resource "azurerm_role_assignment" "node_pool_disk_encryption_set_reader" {
  count = var.disk_encryption_enabled ? 1 : 0

  scope                = azurerm_disk_encryption_set.main[0].id
  role_definition_name = "Reader"
  principal_id         = local.kubelet_object_id
}

#-----------------------------------------------------------------------------------------------------------------------
# Kubeconfig
#
# Two stages, two null_resources: az writes Azure's AAD-mode kubeconfig to
# disk; kubelogin rewrites the exec block to a non-interactive mode so
# terraform's kubernetes provider and kustomize reconcile loops authenticate
# without a devicecode browser prompt.
#
# The write is unconditional once kubeconfig_path is set — operators always
# get a working kubeconfig (in devicecode mode if no override is supplied),
# matching the pre-refactor contract. Conversion is gated on kubelogin_mode
# so non-interactive contexts opt in.
#
# Module owns orchestration only. The CLIs own kubeconfig format (kept current
# by Microsoft, not us). Windsor owns the environment: pre-creates .kube/ in
# the context dir, sets a 077 umask so files land 0600 by default, emits
# TF_VAR_kubelogin_mode from the active Azure credential chain. Operators
# override the auto-detected mode via cluster.kubelogin_mode in values.yaml
# when needed (e.g., MSI on a managed-identity runner).
#
# Triggers stable: cluster_id changes only on cluster recreate, login_mode
# changes only on operator preference flip. Neither resource reads the file
# from disk, so kubelogin's in-place rewrite can't manifest as a perpetual
# plan diff.
#-----------------------------------------------------------------------------------------------------------------------

resource "null_resource" "kubeconfig" {
  count = local.kubeconfig_path != "" ? 1 : 0

  triggers = {
    cluster_id = azurerm_kubernetes_cluster.main.id
  }

  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.main.resource_group_name} --name ${azurerm_kubernetes_cluster.main.name} --file ${local.kubeconfig_path} --overwrite-existing --only-show-errors"
  }
}

resource "null_resource" "convert_kubeconfig" {
  count = local.kubeconfig_path != "" && var.kubelogin_mode != "" ? 1 : 0

  triggers = {
    cluster_id = azurerm_kubernetes_cluster.main.id
    login_mode = var.kubelogin_mode
  }

  provisioner "local-exec" {
    command = "kubelogin convert-kubeconfig -l ${var.kubelogin_mode} --kubeconfig ${local.kubeconfig_path}"
  }

  depends_on = [null_resource.kubeconfig]
}

# Automatically assign "Azure Kubernetes Service RBAC Cluster Admin" to the
# identity running Terraform (the deployer) and any additional admins provided.
# This ensures immediate access when local_account_disabled is set to true.
resource "azurerm_role_assignment" "aks_rbac_admin" {
  for_each = toset(concat(
    [data.azurerm_client_config.current.object_id],
    var.admin_object_ids
  ))

  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

#-----------------------------------------------------------------------------------------------------------------------
# Workload Identity for cert-manager
#
# AKS analogue of the EKS create_cert_manager_role + Pod Identity association
# pair. cert-manager authenticates to Azure DNS via Workload Identity:
# the SA token is exchanged for an Azure AD token via the cluster's OIDC
# issuer, scoped to a User-Assigned Managed Identity with DNS Zone
# Contributor on the specified zone(s). No client secret stored anywhere.
#
# Off by default — only provisioned when ACME is in play (operator set
# dns.public_domain and the facet flips create_cert_manager_identity on).
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "cert_manager" {
  count               = var.create_cert_manager_identity ? 1 : 0
  name                = "${local.cluster_name}-cert-manager"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "cert_manager_dns" {
  for_each             = var.create_cert_manager_identity ? toset(var.cert_manager_dns_zone_ids) : toset([])
  scope                = each.value
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager[0].principal_id
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  count                     = var.create_cert_manager_identity ? 1 : 0
  name                      = "cert-manager"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.cert_manager[0].id
  subject                   = "system:serviceaccount:system-pki:cert-manager"
}

#-----------------------------------------------------------------------------------------------------------------------
# Workload Identity for external-dns
#
# Same pattern as cert-manager. external-dns needs DNS Zone Contributor to
# create / update / delete record sets in the target zone. Default-on so
# any cluster on AKS can publish hostnames once the operator passes a zone
# ID — matches the EKS facet's create_external_dns_role default.
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "external_dns" {
  count               = var.create_external_dns_identity ? 1 : 0
  name                = "${local.cluster_name}-external-dns"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.tags
}

## external-dns enumerates zones via ListByResourceGroup before writing records,
## so the role has to be at RG scope, not per-zone. cert-manager's azureDNS
## solver reads the zone by name + RG directly, so zone-scoped grants are
## fine for it; external-dns has no such shortcut.
##
## Public Azure DNS (Microsoft.Network/dnszones) and Azure Private DNS
## (Microsoft.Network/privateDnsZones) are distinct ARM resource types with
## distinct RBAC roles. Detect the type from the resource ID and assign the
## matching role; mixed lists with both kinds in the same RG produce one
## role assignment per role.
locals {
  external_dns_public_zone_rgs = var.create_external_dns_identity ? toset([
    for id in var.external_dns_dns_zone_ids :
    regex("^(/subscriptions/[^/]+/resourceGroups/[^/]+)", id)[0]
    if can(regex("/dnszones/", lower(id)))
  ]) : toset([])

  external_dns_private_zone_rgs = var.create_external_dns_identity ? toset([
    for id in var.external_dns_dns_zone_ids :
    regex("^(/subscriptions/[^/]+/resourceGroups/[^/]+)", id)[0]
    if can(regex("/privatednszones/", lower(id)))
  ]) : toset([])
}

resource "azurerm_role_assignment" "external_dns_zones" {
  for_each             = local.external_dns_public_zone_rgs
  scope                = each.value
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns[0].principal_id
}

resource "azurerm_role_assignment" "external_dns_private_zones" {
  for_each             = local.external_dns_private_zone_rgs
  scope                = each.value
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns[0].principal_id
}

resource "azurerm_federated_identity_credential" "external_dns" {
  count                     = var.create_external_dns_identity ? 1 : 0
  name                      = "external-dns"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.external_dns[0].id
  subject                   = "system:serviceaccount:system-dns:external-dns"
}
