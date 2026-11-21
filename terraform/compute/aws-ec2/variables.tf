variable "context_id" {
  description = "The windsor context id for this deployment; used to name and tag resources."
  type        = string
  default     = ""
}

variable "context_path" {
  description = "The path to the context folder."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region to launch the nodes in."
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the nodes in. Every fixed node address must fall inside it."
  type        = string
}

variable "talos_version" {
  description = "Talos version whose published AMI the nodes boot, with or without a leading v."
  type        = string
}

variable "controlplanes" {
  description = "Control plane nodes to launch. A node without an address takes one from the subnet."
  type = list(object({
    hostname = string
    node     = optional(string)
  }))

  validation {
    condition     = length(var.controlplanes) > 0
    error_message = "At least one control plane node is required."
  }
}

variable "workers" {
  description = "Worker nodes to launch. A node without an address takes one from the subnet."
  type = list(object({
    hostname = string
    node     = optional(string)
  }))
  default = []
}

variable "controlplane_instance_type" {
  description = "EC2 instance type for control plane nodes. Must be an x86_64, non-burstable type."
  type        = string

  validation {
    condition     = !can(regex("^[a-z]+[0-9]+[a-z]*g[a-z]*\\.", var.controlplane_instance_type))
    error_message = "Only x86_64 instance types are supported; Graviton types such as m7g are not."
  }

  validation {
    condition     = !can(regex("^t[0-9]", var.controlplane_instance_type))
    error_message = "Burstable t-class instance types are not supported."
  }
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes. Defaults to the control plane type. Must be an x86_64, non-burstable type."
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("^[a-z]+[0-9]+[a-z]*g[a-z]*\\.", var.worker_instance_type))
    error_message = "Only x86_64 instance types are supported; Graviton types such as m7g are not."
  }

  validation {
    condition     = !can(regex("^t[0-9]", var.worker_instance_type))
    error_message = "Burstable t-class instance types are not supported."
  }
}

variable "controlplane_root_volume" {
  description = "gp3 root volume for control plane nodes: size in GB, IOPS and throughput in MB/s."
  type = object({
    size       = optional(number, 100)
    iops       = optional(number, 3000)
    throughput = optional(number, 125)
  })
  default = {}

  validation {
    condition     = var.controlplane_root_volume.size >= 8
    error_message = "Root volume size must be at least 8 GB."
  }
}

variable "worker_root_volume" {
  description = "gp3 root volume for worker nodes: size in GB, IOPS and throughput in MB/s."
  type = object({
    size       = optional(number, 100)
    iops       = optional(number, 3000)
    throughput = optional(number, 125)
  })
  default = {}

  validation {
    condition     = var.worker_root_volume.size >= 8
    error_message = "Root volume size must be at least 8 GB."
  }
}

variable "ephemeral" {
  description = "Tags every resource as ephemeral with its creation time, for cleanup of short-lived nodes."
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "KMS key ID, ARN or alias that encrypts the node root volumes. The module creates a key when empty."
  type        = string
  default     = ""
}
