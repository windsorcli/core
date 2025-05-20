# Managed by Windsor CLI: This file is partially managed by the windsor CLI. Your changes will not be overwritten.

# Name of the resource
# name = "cluster"

# Name of the resource group
# resource_group_name = null

# Name of the AKS cluster
# cluster_name = null

# Name on the VNET module
# vnet_module_name = "network"

# ID of the subnet
# vnet_subnet_id = null

# Region for the resources
# region = "eastus"

# Version of Kubernetes to use
# kubernetes_version = "1.32"

# Configuration for the default node pool
# default_node_pool = {
#   host_encryption_enabled = true
#   max_count = null
#   max_pods = null
#   min_count = null
#   name = "system"
#   node_count = null
#   only_critical_addons_enabled = true
#   os_disk_type = "Managed"
#   vm_size = "Standard_D2s_v3"
# }

# Configuration for the autoscaled node pool
# autoscaled_node_pool = {
#   enabled = true
#   host_encryption_enabled = true
#   max_count = null
#   max_pods = null
#   min_count = null
#   mode = "User"
#   name = "autoscaled"
#   os_disk_type = "Managed"
#   vm_size = "Standard_D2s_v3"
# }

# Whether to enable role-based access control for the AKS cluster
# role_based_access_control_enabled = true

# Configuration for the AKS cluster's auto-scaler
# auto_scaler_profile = {
#   balance_similar_node_groups = true
#   max_graceful_termination_sec = null
#   scale_down_delay_after_add = "10m"
#   scale_down_delay_after_delete = "10s"
#   scale_down_delay_after_failure = "3m"
#   scale_down_unneeded = "10m"
#   scale_down_unready = "20m"
#   scale_down_utilization_threshold = "0.5"
#   scan_interval = "10s"
# }

# Configuration for the AKS cluster's workload autoscaler
# workload_autoscaler_profile = {
#   keda_enabled = false
#   vertical_pod_autoscaler_enabled = false
# }

# The automatic upgrade channel for the AKS cluster
# automatic_upgrade_channel = "stable"

# The SKU tier for the AKS cluster
# sku_tier = "Standard"

# Whether to enable private cluster for the AKS cluster
# private_cluster_enabled = false

# Whether to enable Azure Policy for the AKS cluster
# azure_policy_enabled = true

# Whether to disable local accounts for the AKS cluster
# local_account_disabled = false

# Whether to enable public network access for the AKS cluster
# public_network_access_enabled = true

# The default action for the AKS cluster's network ACLs
# network_acls_default_action = "Allow"

# The expiration date for the AKS cluster's key vault
# expiration_date = null

# Additional user assigned identity IDs for the AKS cluster
# additional_cluster_identity_ids = []

# The number of days to retain the AKS cluster's key vault
# soft_delete_retention_days = null

# Tags to apply to the resources
# tags = {}
