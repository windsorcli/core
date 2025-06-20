variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig and talosconfig are stored"
  default     = ""
}

variable "os_type" {
  description = "The operating system type, must be either 'unix' or 'windows'"
  type        = string
  default     = "unix"
  validation {
    condition     = var.os_type == "unix" || var.os_type == "windows"
    error_message = "The operating system type must be either 'unix' or 'windows'."
  }
}

variable "kubernetes_version" {
  description = "The kubernetes version to deploy."
  type        = string
  # renovate: datasource=github-releases depName=kubernetes package=kubernetes/kubernetes
  default = "1.33.1"
  validation {
    condition     = can(regex("^1\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in semantic version format like '1.30.3'."
  }
}

variable "talos_version" {
  description = "The talos version to deploy."
  type        = string
  # renovate: datasource=github-releases depName=talos package=siderolabs/talos
  default = "1.10.4"
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "The Talos version should be in semantic version format like '1.7.6'."
  }
}

variable "platform" {
  description = "The target platform for the Talos installer image (e.g., metal, aws, gcp, azure, local)."
  type        = string
  default     = "metal"
  validation {
    condition = contains([
      "metal", "aws", "gcp", "azure", "vmware", "equinixMetal", "hcloud", "digitalocean",
      "scaleway", "upcloud", "vultr", "exoscale", "oracle", "nocloud", "local"
    ], var.platform)
    error_message = "Platform must be one of: metal, aws, gcp, azure, vmware, equinixMetal, hcloud, digitalocean, scaleway, upcloud, vultr, exoscale, oracle, nocloud, local."
  }
}

variable "installer_image" {
  description = "Optional override for the Talos installer image. If not specified, will be automatically generated based on platform and talos_version. Examples: 'factory.talos.dev/metal-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v1.8.2', 'ghcr.io/myorg/custom-installer:v1.8.2'"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "The name of the cluster."
  type        = string
  default     = "talos"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "Cluster name cannot be empty."
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
