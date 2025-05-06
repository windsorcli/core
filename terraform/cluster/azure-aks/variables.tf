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

variable "role_based_access_control_enabled" {
  type        = bool
  description = "Whether to enable role-based access control for the AKS cluster"
  default     = true
}

variable "auto_scaler_profile" {
  type        = map(string)
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
  type        = map(string)
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

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "The API server authorized IP ranges for the AKS cluster"
  default     = ["0.0.0.0/0"]
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

variable "os_disk_type" {
  type        = string
  description = "The type of OS disk for the AKS cluster"
  default     = "Managed"
}

variable "host_encryption_enabled" {
  type        = bool
  description = "Whether to enable host encryption for the AKS cluster"
  default     = true
}

variable "max_pods" {
  type        = number
  description = "The maximum number of pods for the AKS cluster"
  default     = 50
}

variable "min_count" {
  type        = number
  description = "The minimum number of nodes for the AKS cluster"
  default     = 1
}

variable "max_count" {
  type        = number
  description = "The maximum number of nodes for the AKS cluster"
  default     = 3
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
