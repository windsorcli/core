# -----------------------------------------------------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------------------------------------------------

variable "context" {
  description = "The windsor context id for this deployment. Typically set implicitly via TF_VAR_context."
  type        = string
  default     = ""
}

variable "context_id" {
  description = "Alias for var.context."
  type        = string
  default     = ""
}

variable "talos_version" {
  description = "Pinned Talos version (semver, no v-prefix). Used to call the secrets submodule and to stamp machineconfig templates. Must match the talos_version cluster/talos consumes."
  type        = string
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version should be in semver format like '1.12.6'."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install. Mirrors cluster/talos's default."
  type        = string
  # renovate: datasource=github-releases depName=kubernetes package=kubernetes/kubernetes
  default = "1.36.4"
}

variable "cluster_name" {
  description = "Talos cluster name. Must match what cluster/talos uses."
  type        = string
  default     = "talos"
}

variable "cluster_endpoint" {
  description = "Cluster control-plane API endpoint baked into every per-node machineconfig (e.g. https://<vip-or-cp1>:6443). Empty skips the CIDATA machineconfig bake so cluster/talos can apply after DHCP leases exist."
  type        = string
  default     = ""
  validation {
    condition     = var.cluster_endpoint == "" || can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be empty or start with https://"
  }
}

variable "controlplanes" {
  description = "Per-node controlplane definitions. hostname/node mirror compute output and cluster.controlplanes.nodes shape; address is the static IP delivered via CIDATA's network-config. Omit node/address when network.dhcp is true."
  type = list(object({
    hostname = string
    node     = optional(string)
    address  = optional(string)
  }))
  default = []
}

variable "workers" {
  description = "Per-node worker definitions. Same shape as controlplanes."
  type = list(object({
    hostname = string
    node     = optional(string)
    address  = optional(string)
  }))
  default = []
}

variable "network" {
  description = "Network config baked into each guest's CIDATA seed. cidr_block's prefix length is reused when a node's address is unset. interface is a netplan name glob (default e* matches eth0 and enX0). dhcp true writes dhcp4 instead of static addresses."
  type = object({
    cidr_block  = optional(string)
    gateway     = optional(string)
    nameservers = optional(list(string), [])
    interface   = optional(string, "e*")
    dhcp        = optional(bool, false)
  })

  validation {
    condition     = var.network.dhcp == true || (var.network.cidr_block != null && var.network.gateway != null)
    error_message = "network.cidr_block and network.gateway are required unless network.dhcp is true"
  }

  validation {
    condition = var.network.dhcp == true || alltrue([
      for n in concat(var.controlplanes, var.workers) : n.node != null && n.node != ""
    ])
    error_message = "each controlplane and worker must set node unless network.dhcp is true"
  }
}

variable "destination_dir" {
  description = "Directory on the host where per-node CIDATA ISOs land."
  type        = string
}

variable "name_suffix" {
  description = "Suffix for CIDATA ISO filenames. Keeps two contexts sharing one host from writing the same seed path."
  type        = string
  default     = ""
}

variable "common_config_patches" {
  description = "Cluster-wide Talos machine config patch (YAML string). Same value cluster/talos consumes; applied to every node's machineconfig before CIDATA wrapping so the same patches reach the cluster regardless of delivery method."
  type        = string
  default     = ""
}

variable "controlplane_config_patches" {
  description = "Controlplane-only Talos machine config patch (YAML string)."
  type        = string
  default     = ""
}

variable "worker_config_patches" {
  description = "Worker-only Talos machine config patch (YAML string)."
  type        = string
  default     = ""
}
