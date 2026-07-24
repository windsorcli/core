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
  default = "1.36.3"
}

variable "cluster_name" {
  description = "Talos cluster name. Must match what cluster/talos uses."
  type        = string
  default     = "talos"
}

variable "cluster_endpoint" {
  description = "Cluster control-plane API endpoint baked into every per-node machineconfig (e.g. https://<vip-or-cp1>:6443). Must be reachable from worker nodes once the cluster is up."
  type        = string
  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must start with https://"
  }
}

variable "controlplanes" {
  description = "Per-node controlplane definitions. hostname/node mirror compute output and cluster.controlplanes.nodes shape; address is the static IP delivered via CIDATA's network-config."
  type = list(object({
    hostname = string
    node     = string
    address  = optional(string) # static IP in CIDR form (e.g. 192.168.0.10/22). Defaults to "${node}/${prefix}".
  }))
  default = []
}

variable "workers" {
  description = "Per-node worker definitions. Same shape as controlplanes."
  type = list(object({
    hostname = string
    node     = string
    address  = optional(string)
  }))
  default = []
}

variable "network" {
  description = "Network config baked into each guest's CIDATA seed. cidr_block's prefix length is reused when a node's address is unset. interface is a netplan name glob (default e* matches eth0 and enX0)."
  type = object({
    cidr_block  = string
    gateway     = string
    nameservers = list(string)
    interface   = optional(string, "e*")
  })
}

variable "destination_dir" {
  description = "Directory on the host where per-node CIDATA ISOs land."
  type        = string
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
