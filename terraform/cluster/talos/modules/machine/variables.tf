variable "machine_type" {
  description = "The machine type, which must be either 'controlplane' or 'worker'."
  type        = string
  validation {
    condition     = can(regex("^(controlplane|worker)$", var.machine_type))
    error_message = "The machine type must be 'controlplane' or 'worker'."
  }
}

variable "endpoint" {
  description = "The endpoint of the machine."
  type        = string
}

variable "node" {
  description = "The node address of the machine."
  type        = string
}

variable "disk_selector" {
  description = "The disk selector to use for the machine."
  type = object({
    busPath  = string
    modalias = string
    model    = string
    name     = string
    serial   = string
    size     = string
    type     = string
    uuid     = string
    wwid     = string
  })
  default = null
}

variable "image" {
  description = "The Talos image to install."
  type        = string
  default     = "ghcr.io/siderolabs/installer:latest"
}

variable "wipe_disk" {
  description = "Indicates whether to wipe the install disk."
  type        = bool
  default     = true
}

variable "extra_kernel_args" {
  description = "Additional kernel arguments to pass to the machine."
  type        = list(string)
  default     = []
}

variable "extensions" {
  description = "The extensions to use for the machine."
  type        = list(object({ image = string }))
  default     = []
}

variable "client_configuration" {
  description = "The Talos client configuration."
  type        = any
}

variable "machine_secrets" {
  description = "The Talos machine secrets."
  type        = any
}

variable "cluster_name" {
  description = "The name of the cluster."
  type        = string
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster name must not be empty."
  }
}

variable "hostname" {
  description = "The hostname of the machine."
  type        = string
  default     = ""
}

variable "cluster_endpoint" {
  description = "The cluster endpoint."
  type        = string
  validation {
    condition     = var.cluster_endpoint == "" || can(regex("^https://", var.cluster_endpoint))
    error_message = "The API endpoint must start with 'https://'."
  }
}

variable "kubernetes_version" {
  description = "The Kubernetes version."
  type        = string
}

variable "talos_version" {
  description = "The Talos version."
  type        = string
}

variable "config_patches" {
  description = "The configuration patches to apply to the machine."
  type        = list(string)
  default     = []
}

variable "bootstrap" {
  description = "Indicates whether to bootstrap the machine."
  type        = bool
  default     = false
}

variable "talosconfig_path" {
  description = "Path to the talosconfig file for health checking."
  type        = string
}

variable "enable_health_check" {
  description = "Whether to enable health checking for this node."
  type        = bool
  default     = true
}
