#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "vnet_resource_group_name" {
  description = "Name of the VNET resource group"
  type        = string
  default     = null
}

variable "vnet_name" {
  description = "Name of the VNET"
  type        = string
  default     = null
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

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Version of Kubernetes to use"
  type        = string
  default     = "1.32"
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

variable "default_node_pool" {
  description = "Configuration for the default node pool"
  type = object({
    name                    = string
    vm_size                 = string
    os_disk_type            = string
    max_pods                = number
    host_encryption_enabled = bool
    min_count               = number
    max_count               = number
    node_count              = number
  })
  default = {
    name                    = "system"
    vm_size                 = "Standard_D2s_v3"
    os_disk_type            = "Managed"
    max_pods                = 30
    host_encryption_enabled = true
    min_count               = 1
    max_count               = 3
    node_count              = 1
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
  })
  default = {
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
  default     = false
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
