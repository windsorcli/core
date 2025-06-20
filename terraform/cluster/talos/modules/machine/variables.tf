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

variable "installer_image" {
  description = "Optional override for the Talos installer image. If not specified, will be automatically generated based on platform and talos_version. Examples: 'factory.talos.dev/metal-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v1.8.2', 'ghcr.io/myorg/custom-installer:v1.8.2'"
  type        = string
  default     = ""
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
