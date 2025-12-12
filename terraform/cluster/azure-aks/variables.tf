#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "admin_object_ids" {
  type        = list(string)
  description = "List of Azure AD Object IDs (User or Group) to assign 'Azure Kubernetes Service RBAC Cluster Admin' role. Required when local_account_disabled is true to ensure access."
  default     = []
}

variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig is stored"
  default     = ""
}

variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  default     = null
}

variable "name" {
  description = "Name of the resource"
  type        = string
  default     = "cluster"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = null
}

variable "vnet_module_name" {
  description = "Name on the VNET module"
  type        = string
  default     = "network"
}

variable "vnet_subnet_id" {
  description = "ID of the subnet"
  type        = string
  default     = null
}

variable "region" {
  description = "Region for the resources"
  type        = string
  default     = "eastus"
}

variable "kubernetes_version" {
  description = "Version of Kubernetes to use"
  type        = string
  # renovate: datasource=github-tags depName=aks-kubernetes package=windsorcli/k8s-versions
  default = "1.32"
  validation {
    condition     = can(regex("^1\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in version format like '1.32'."
  }
}

variable "default_node_pool" {
  description = "Configuration for the default node pool"
  type = object({
    name                         = string
    vm_size                      = string
    os_disk_type                 = string
    max_pods                     = number
    host_encryption_enabled      = bool
    min_count                    = number
    max_count                    = number
    node_count                   = number
    only_critical_addons_enabled = bool
    availability_zones           = optional(list(string))
    upgrade_settings = optional(object({
      drain_timeout_in_minutes      = number
      max_surge                     = string
      node_soak_duration_in_minutes = number
    }))
  })
  default = {
    name                         = "system"
    vm_size                      = "Standard_D2s_v3"
    os_disk_type                 = "Managed"
    max_pods                     = 48
    host_encryption_enabled      = true
    min_count                    = 1
    max_count                    = 3
    node_count                   = 1
    only_critical_addons_enabled = true
    upgrade_settings = {
      drain_timeout_in_minutes      = 30
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 10
    }
  }
}

variable "autoscaled_node_pool" {
  description = "Configuration for the autoscaled node pool"
  type = object({
    enabled                 = bool
    name                    = string
    vm_size                 = string
    mode                    = string
    os_disk_type            = string
    max_pods                = number
    host_encryption_enabled = bool
    min_count               = number
    max_count               = number
    availability_zones      = optional(list(string))
    upgrade_settings = optional(object({
      drain_timeout_in_minutes      = number
      max_surge                     = string
      node_soak_duration_in_minutes = number
    }))
  })
  default = {
    enabled                 = true
    name                    = "autoscaled"
    vm_size                 = "Standard_D2s_v3"
    mode                    = "User"
    os_disk_type            = "Managed"
    max_pods                = 48
    host_encryption_enabled = true
    min_count               = 1
    max_count               = 3
  }
}

variable "role_based_access_control_enabled" {
  type        = bool
  description = "Whether to enable role-based access control for the AKS cluster"
  default     = true
}

variable "auto_scaler_profile" {
  type = object({
    balance_similar_node_groups      = bool
    max_graceful_termination_sec     = number
    scale_down_delay_after_add       = string
    scale_down_delay_after_delete    = string
    scale_down_delay_after_failure   = string
    scan_interval                    = string
    scale_down_unneeded              = string
    scale_down_unready               = string
    scale_down_utilization_threshold = string
  })
  description = "Configuration for the AKS cluster's auto-scaler"
  default = {
    balance_similar_node_groups      = true
    max_graceful_termination_sec     = 600
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scan_interval                    = "10s"
    scale_down_unneeded              = "10m"
    scale_down_unready               = "20m"
    scale_down_utilization_threshold = "0.5"
  }
}

variable "workload_autoscaler_profile" {
  type = object({
    keda_enabled                    = bool
    vertical_pod_autoscaler_enabled = bool
  })
  description = "Configuration for the AKS cluster's workload autoscaler"
  default = {
    keda_enabled                    = false
    vertical_pod_autoscaler_enabled = false
  }
}

variable "automatic_upgrade_channel" {
  type        = string
  description = "The automatic upgrade channel for the AKS cluster"
  default     = "stable"
}

variable "sku_tier" {
  type        = string
  description = "The SKU tier for the AKS cluster"
  default     = "Standard"
}

variable "private_cluster_enabled" {
  type        = bool
  description = "Whether to enable private cluster for the AKS cluster"
  default     = false
}

variable "azure_policy_enabled" {
  type        = bool
  description = "Whether to enable Azure Policy for the AKS cluster"
  default     = true
}

variable "local_account_disabled" {
  type        = bool
  description = "Whether to disable local accounts for the AKS cluster"
  default     = true
}

variable "authorized_ip_ranges" {
  type        = set(string)
  description = "Set of authorized IP ranges to allow access to the API server. If null, allows all (0.0.0.0/0)."
  default     = null
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Whether to enable public network access for the AKS cluster"
  default     = true
}

variable "network_acls_default_action" {
  type        = string
  description = "The default action for the AKS cluster's network ACLs"
  default     = "Allow"
}

variable "expiration_date" {
  type        = string
  description = "The expiration date for the AKS cluster's key vault"
  default     = null
}

variable "soft_delete_retention_days" {
  type        = number
  description = "The number of days to retain the AKS cluster's key vault"
  default     = 7
}

variable "tags" {
  description = "Tags to apply to the resources"
  type        = map(string)
  default     = {}
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.96.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.96.0.10"
}

variable "endpoint_private_access" {
  description = "Whether to enable private access to the Kubernetes API server"
  type        = bool
  default     = false
}

variable "disk_encryption_enabled" {
  description = "Whether to enable disk encryption using Customer-Managed Keys (CMK) for the AKS cluster"
  type        = bool
  default     = true
}

variable "key_vault_key_id" {
  description = "The ID of an existing Key Vault key to use for disk encryption. If null, a new key will be created."
  type        = string
  default     = null
}

variable "outbound_type" {
  description = "The outbound (egress) routing method which should be used for this Kubernetes Cluster."
  type        = string
  default     = "userAssignedNATGateway"
  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "The outbound_type must be one of: loadBalancer, userDefinedRouting, managedNATGateway, userAssignedNATGateway."
  }
}

variable "enable_volume_snapshots" {
  description = "Enable volume snapshot permissions for the kubelet identity. Set to false to use minimal permissions if volume snapshots are not needed."
  type        = bool
  default     = true
}

variable "oidc_issuer_enabled" {
  description = "Enable OIDC issuer for the AKS cluster"
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "Enable Workload Identity for the AKS cluster"
  type        = bool
  default     = true
}

variable "diagnostic_log_categories" {
  type        = set(string)
  description = "Set of log categories to send to Log Analytics. Default excludes expensive 'kube-audit'"
  default = [
    "kube-audit-admin",
    "kube-controller-manager",
    "cluster-autoscaler",
    "guard",
    "kube-scheduler"
  ]
}

variable "diagnostic_log_retention_days" {
  type        = number
  description = "Number of days to retain diagnostic logs. If null, uses the Log Analytics Workspace default retention period."
  default     = null
}

variable "container_insights_enabled" {
  type        = bool
  description = "Enable Azure Monitor Container Insights for collecting container logs, Kubernetes events, and pod/node inventory. Disable for cost-sensitive dev/test environments or when using alternative monitoring solutions."
  default     = false
}

variable "image_cleaner_enabled" {
  description = "Enable Image Cleaner for the AKS cluster"
  type        = bool
  default     = true
}

variable "image_cleaner_interval_hours" {
  description = "Interval in hours for Image Cleaner to run"
  type        = number
  default     = 48
}

variable "kubelogin_mode" {
  description = "Login mode for kubelogin convert-kubeconfig. If set, converts the kubeconfig to use this login mode. Valid values: devicecode, interactive, spn, ropc, msi, azurecli, azd, workloadidentity, azurepipelines. Leave empty to skip conversion and use the default devicecode mode from Azure."
  type        = string
  default     = ""
  validation {
    condition = var.kubelogin_mode == "" || contains([
      "devicecode",
      "interactive",
      "spn",
      "ropc",
      "msi",
      "azurecli",
      "azd",
      "workloadidentity",
      "azurepipelines"
    ], var.kubelogin_mode)
    error_message = "kubelogin_mode must be empty or one of: devicecode, interactive, spn, ropc, msi, azurecli, azd, workloadidentity, azurepipelines."
  }
}

