variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig and talosconfig are stored"
  default     = ""
}

variable "kubernetes_version" {
  description = "The kubernetes version to deploy."
  type        = string
  # renovate: datasource=github-releases depName=kubernetes package=kubernetes/kubernetes
  default = "1.36.3"
  validation {
    condition     = can(regex("^1\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in semantic version format like '1.30.3'."
  }
}

variable "talos_version" {
  description = "The talos version to deploy. Must match the node image tag (e.g. 1.12.1 for ghcr.io/siderolabs/talos:v1.12.1)."
  type        = string
  # renovate: datasource=github-releases depName=talos package=siderolabs/talos
  default = "1.13.7"
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "The Talos version should be in semantic version format like '1.7.6'."
  }
}

# Pre-generated cluster identity from an upstream cluster/talos-secrets module.
# When BOTH are null (default — incus/metal/docker/aws/azure callers): cluster/talos
# generates secrets locally via talos_machine_secrets and applies per-node configs
# over the maintenance-mode Talos API. When BOTH are supplied (hyperv path): the
# secrets came from cluster/talos-secrets (which also feeds cluster/talos/config to
# wrap signed configs into CIDATA seed ISOs). cluster/talos then skips
# talos_machine_configuration_apply because the configs are already on the nodes
# via CIDATA, and goes straight to talos_machine_bootstrap + health checks.
variable "machine_secrets" {
  description = "Pre-generated Talos machine_secrets (output of an upstream cluster/talos-secrets module). When null (default), cluster/talos generates its own. Must be supplied together with client_configuration."
  type        = any
  sensitive   = true
  default     = null
}

variable "client_configuration" {
  description = "Pre-generated Talos client_configuration (output of an upstream cluster/talos-secrets module). When null (default), cluster/talos derives it from the locally-generated talos_machine_secrets. Must be supplied together with machine_secrets."
  type        = any
  sensitive   = true
  default     = null
  validation {
    condition     = (var.machine_secrets == null) == (var.client_configuration == null)
    error_message = "machine_secrets and client_configuration must be supplied together (both null = generate locally; both set = use upstream)."
  }
}

# talos_node_image is a literal mirror pin for the Talos node image. Windsor's
# mirror scanner follows this exact docker reference so `windsor mirror`
# includes the Talos image in the air-gapped registry. Renovate's docker
# manager keeps it in sync with talos_version via the annotation below.
variable "talos_node_image" {
  description = "Literal Talos node image reference used to pin the image for mirror hydration. Kept in sync with talos_version by Renovate."
  type        = string
  # renovate: datasource=docker depName=ghcr.io/siderolabs/talos packageName=ghcr.io/siderolabs/talos
  default = "ghcr.io/siderolabs/talos:v1.12.6"
}

variable "cluster_name" {
  description = "The name of the cluster."
  type        = string
  default     = "talos"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster name must not be empty."
  }
}

variable "cluster_endpoint" {
  description = "The external controlplane API endpoint (https://host:6443). If empty, derived from first controlplane's endpoint (Talos host:port → https://host:6443)."
  type        = string
  default     = "https://localhost:6443"
  validation {
    condition     = var.cluster_endpoint == "" || can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be empty or start with 'https://'."
  }
}

variable "controlplanes" {
  description = "A list of machine configuration details for control planes."
  type = list(object({
    endpoint = string
    node     = string
    disks    = optional(list(any), [])
    disk_selector = optional(object({
      busPath  = optional(string)
      modalias = optional(string)
      model    = optional(string)
      name     = optional(string)
      serial   = optional(string)
      size     = optional(string)
      type     = optional(string)
      uuid     = optional(string)
      wwid     = optional(string)
    }))
    wipe_disk         = optional(bool, true)
    extra_kernel_args = optional(list(string), [])
    config_patches    = optional(string, "")
  }))
  default = []

  validation {
    condition     = alltrue([for controlplane in var.controlplanes : controlplane.config_patches == "" || can(yamldecode(controlplane.config_patches))])
    error_message = "Each controlplane's config_patches must be an empty string or a valid YAML string."
  }
}

variable "workers" {
  description = "A list of machine configuration details"
  type = list(object({
    endpoint = string
    node     = string
    disks    = optional(list(any), [])
    disk_selector = optional(object({
      busPath  = optional(string)
      modalias = optional(string)
      model    = optional(string)
      name     = optional(string)
      serial   = optional(string)
      size     = optional(string)
      type     = optional(string)
      uuid     = optional(string)
      wwid     = optional(string)
    }))
    wipe_disk         = optional(bool, true)
    extra_kernel_args = optional(list(string), [])
    config_patches    = optional(string, "")
  }))
  default = []

  validation {
    condition     = alltrue([for worker in var.workers : worker.config_patches == "" || can(yamldecode(worker.config_patches))])
    error_message = "Each worker's config_patches must be an empty string or a valid YAML string."
  }
}

variable "common_config_patches" {
  description = "A YAML string of common config patches to apply. Can be an empty string or valid YAML."
  type        = string
  default     = ""
  validation {
    condition     = var.common_config_patches == "" || can(yamldecode(var.common_config_patches))
    error_message = "common_config_patches must be an empty string or a valid YAML string."
  }
}

variable "controlplane_config_patches" {
  description = "A YAML string of controlplane config patches to apply. Can be an empty string or valid YAML."
  type        = string
  default     = ""
  validation {
    condition     = var.controlplane_config_patches == "" || can(yamldecode(var.controlplane_config_patches))
    error_message = "controlplane_config_patches must be an empty string or a valid YAML string."
  }
}

variable "worker_config_patches" {
  description = "A YAML string of worker config patches to apply. Can be an empty string or valid YAML."
  type        = string
  default     = ""
  validation {
    condition     = var.worker_config_patches == "" || can(yamldecode(var.worker_config_patches))
    error_message = "worker_config_patches must be an empty string or a valid YAML string."
  }
}

variable "worker_volumes" {
  description = "Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present)."
  type        = list(string)
  default     = []
}

variable "controlplane_volumes" {
  description = "Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present)."
  type        = list(string)
  default     = []
}

variable "controlplane_disks" {
  description = "Pool-level disks; used when a controlplane node has no disks key. Per-node disks override."
  type        = list(any)
  default     = []
}

variable "worker_disks" {
  description = "Pool-level disks; used when a worker node has no disks key. Per-node disks override."
  type        = list(any)
  default     = []
}

