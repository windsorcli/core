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

variable "private_subnet_ids" {
  description = "Private subnet IDs the AKS node pools attach to. Default node pool uses the first; the autoscaled pool uses the last. Pipe network/azure-vnet's private_subnet_ids output."
  type        = list(string)
  default     = null
  validation {
    condition     = var.private_subnet_ids != null && length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids is required and must be non-empty. The VNet/subnet data lookup this module previously used has been removed; pipe network/azure-vnet's private_subnet_ids output, e.g. inputs.private_subnet_ids = terraform_output('network', 'private_subnet_ids') in the platform-azure facet."
  }
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
  default = "1.34"
  validation {
    condition     = can(regex("^1\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in version format like '1.34'."
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
    name = "system"
    # D2s_v5 is current-gen (D2s_v3 is two generations behind, retired tier),
    # same 2 vCPU / 8 GB but better price/perf. System pool stays small —
    # only_critical_addons_enabled puts a CriticalAddonsOnly:NoSchedule taint
    # on it, so user workloads avoid it; this pool only hosts cluster operators.
    vm_size                      = "Standard_D2s_v5"
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
    enabled = true
    name    = "autoscaled"
    # D4s_v5 (4 vCPU / 16 GB) — sized for the heavy core stack (kube-prometheus
    # stack alone wants ~2 GB, plus fluentd/fluent-bit/cert-manager/kyverno).
    # D2s_v3 (8 GB) was tight: nodes evicted under steady state on fresh installs.
    vm_size                 = "Standard_D4s_v5"
    mode                    = "User"
    os_disk_type            = "Managed"
    max_pods                = 48
    host_encryption_enabled = true
    min_count               = 1
    max_count               = 3
    # Match Azure's at-create defaults exactly so the dynamic block always
    # renders. Without these, the block isn't emitted, Azure populates its
    # own defaults, and every subsequent plan tries to "remove" the block
    # the API just added back.
    upgrade_settings = {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }
}

variable "pools" {
  description = "Portable user-pool definitions, keyed by pool name. Mirrors the AWS-EKS shape: each entry maps a class (system/general/compute/memory/storage/gpu/arm64) to an additional AKS user node pool. The cluster's inline default node pool is unaffected and remains the system pool — pools is purely additive."
  type = map(object({
    class          = string
    count          = number
    lifecycle      = optional(string, "on-demand")
    instance_types = optional(list(string))
    root_disk_size = optional(number)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.pools : contains(
        ["system", "general", "compute", "memory", "storage", "gpu", "arm64"],
        v.class
      )
    ])
    error_message = "Each pool's class must be one of: system, general, compute, memory, storage, gpu, arm64."
  }

  validation {
    condition = alltrue([
      for k, v in var.pools :
      contains(["on-demand", "spot"], v.lifecycle)
    ])
    error_message = "Each pool's lifecycle must be 'on-demand' or 'spot'."
  }

  validation {
    condition     = alltrue([for k, v in var.pools : v.count >= 0])
    error_message = "Each pool's count must be >= 0."
  }
}

variable "class_instance_types" {
  description = "Default Azure VM size list per portable pool class. Multi-size lists guard against single-SKU capacity shortages in a region. A pool's explicit instance_types overrides this map. When overriding this variable, all seven class keys must be supplied — partial overrides are rejected at validate time."
  type        = map(list(string))
  default = {
    system  = ["Standard_D2s_v5", "Standard_D2as_v5", "Standard_D4s_v5", "Standard_D4as_v5"]
    general = ["Standard_D4s_v5", "Standard_D4as_v5", "Standard_D8s_v5", "Standard_D8as_v5"]
    compute = ["Standard_F4s_v2", "Standard_F8s_v2", "Standard_F16s_v2"]
    memory  = ["Standard_E4s_v5", "Standard_E4as_v5", "Standard_E8s_v5"]
    storage = ["Standard_L8s_v3", "Standard_L16s_v3"]
    gpu     = ["Standard_NC4as_T4_v3", "Standard_NC8as_T4_v3"]
    arm64   = ["Standard_D2pds_v5", "Standard_D4pds_v5", "Standard_E4pds_v5"]
  }

  validation {
    condition = alltrue([
      for c in ["system", "general", "compute", "memory", "storage", "gpu", "arm64"] :
      contains(keys(var.class_instance_types), c) && length(lookup(var.class_instance_types, c, [])) > 0
    ])
    error_message = "class_instance_types must contain a non-empty list for every pool class: system, general, compute, memory, storage, gpu, arm64."
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

variable "create_cert_manager_identity" {
  description = "Whether to provision a User-Assigned Managed Identity, DNS Zone Contributor role assignments, and Federated Identity Credential for cert-manager's azureDNS ACME DNS-01 solver. Enable when cert-manager will issue ACME certificates against an Azure DNS zone."
  type        = bool
  default     = false
}

variable "cert_manager_dns_zone_ids" {
  description = "Full Azure resource IDs of DNS zones cert-manager is allowed to write ACME challenge records to. The DNS Zone Contributor role assignment is scoped to these zones — leave empty when create_cert_manager_identity is false."
  type        = list(string)
  default     = []
}

variable "create_external_dns_identity" {
  description = "Whether to provision a User-Assigned Managed Identity, DNS Zone Contributor role assignments, and Federated Identity Credential for external-dns. Enable when external-dns will publish records to an Azure DNS zone."
  type        = bool
  default     = true
}

variable "external_dns_dns_zone_ids" {
  description = "Full Azure resource IDs of DNS zones external-dns is allowed to manage records in. The DNS Zone Contributor role assignment is scoped to these zones — leave empty when create_external_dns_identity is false."
  type        = list(string)
  default     = []
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

