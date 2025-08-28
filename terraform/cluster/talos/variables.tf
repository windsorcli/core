variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig and talosconfig are stored"
  default     = ""
}

variable "kubernetes_version" {
  description = "The kubernetes version to deploy."
  type        = string
  # renovate: datasource=github-releases depName=kubernetes package=kubernetes/kubernetes
  default = "1.34.0"
  validation {
    condition     = can(regex("^1\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in semantic version format like '1.30.3'."
  }
}

variable "talos_version" {
  description = "The talos version to deploy."
  type        = string
  # renovate: datasource=github-releases depName=talos package=siderolabs/talos
  default = "1.10.7"
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "The Talos version should be in semantic version format like '1.7.6'."
  }
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
  description = "The external controlplane API endpoint of the kubernetes API."
  type        = string
  default     = "https://localhost:6443"
  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "The external controlplane API endpoint must start with 'https://'."
  }
}

variable "controlplanes" {
  description = "A list of machine configuration details for control planes."
  type = list(object({
    hostname = optional(string)
    endpoint = string
    node     = string
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
    hostname = optional(string)
    endpoint = string
    node     = string
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
