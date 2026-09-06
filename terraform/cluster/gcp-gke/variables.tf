#---------------------------------------------------------------------------------------------------
# General Context
#---------------------------------------------------------------------------------------------------

variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig is stored"
  default     = ""
}

variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  validation {
    condition     = var.context_id != null && var.context_id != ""
    error_message = "context_id must be provided and cannot be empty."
  }
}

variable "name" {
  description = "Name prefix for the GKE cluster"
  type        = string
  default     = "cluster"
}

variable "cluster_name" {
  description = "Name of the GKE cluster. If not provided, a default name will be generated"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "GCP project ID the cluster is created in"
  type        = string
  validation {
    condition     = var.project_id != null && var.project_id != ""
    error_message = "project_id must be provided and cannot be empty."
  }
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "us-central1"
}

#---------------------------------------------------------------------------------------------------
# Networking
#---------------------------------------------------------------------------------------------------

variable "network_id" {
  description = "ID of the VPC network the cluster attaches to. Pipe network/gcp-vpc's network_id output."
  type        = string
  validation {
    condition     = var.network_id != null && var.network_id != ""
    error_message = "network_id is required; pipe network/gcp-vpc's network_id output."
  }
}

variable "subnetwork_id" {
  description = "ID of the private subnet nodes attach to. Pipe network/gcp-vpc's private_subnet_id output."
  type        = string
  validation {
    condition     = var.subnetwork_id != null && var.subnetwork_id != ""
    error_message = "subnetwork_id is required; pipe network/gcp-vpc's private_subnet_id output."
  }
}

variable "master_ipv4_cidr_block" {
  description = "A /28 CIDR block for the private control plane's internal address, disjoint from every subnet in the VPC"
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = "CIDR blocks allowed to reach the control plane's public endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

#---------------------------------------------------------------------------------------------------
# Cluster
#---------------------------------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, or STABLE"
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of: RAPID, REGULAR, STABLE."
  }
}

#---------------------------------------------------------------------------------------------------
# System Node Pool
#---------------------------------------------------------------------------------------------------

variable "system_node_pool" {
  description = "Configuration for the system node pool"
  type = object({
    machine_type        = string
    disk_size_gb        = number
    node_count          = number
    autoscaling_enabled = bool
    min_count           = number
    max_count           = number
  })
  default = {
    # e2-standard-2 (2 vCPU / 8 GB) for broad zonal availability at low cost.
    # System pool stays small — the CriticalAddonsOnly taint keeps user
    # workloads off it, this pool only hosts cluster operators.
    machine_type        = "e2-standard-2"
    disk_size_gb        = 50
    node_count          = 1
    autoscaling_enabled = true
    min_count           = 1
    max_count           = 3
  }
}

#---------------------------------------------------------------------------------------------------
# Portable User Pools
#---------------------------------------------------------------------------------------------------

variable "pools" {
  description = "Portable user-pool definitions, keyed by pool name; mirrors the AWS-EKS/AKS pools input. Empty falls back to one autoscaling general pool. Autoscaling defaults on (min 1, max 3) for every class except system."
  type = map(object({
    class          = string
    count          = number
    lifecycle      = optional(string, "on-demand")
    instance_types = optional(list(string))
    root_disk_size = optional(number)
    autoscaling = optional(object({
      enabled = optional(bool)
      min     = optional(number)
      max     = optional(number)
    }))
    labels = optional(map(string), {})
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

  validation {
    condition = alltrue([
      for k, v in var.pools :
      try(v.autoscaling.min <= v.autoscaling.max, true)
    ])
    error_message = "Each pool's autoscaling.min must be <= autoscaling.max."
  }

  validation {
    condition = alltrue([
      for k, v in var.pools :
      v.autoscaling == null ? true : (
        v.autoscaling.enabled == false
        || (v.autoscaling.enabled == null && v.class == "system")
        || (v.count >= coalesce(v.autoscaling.min, min(v.count, 1)) && v.count <= coalesce(v.autoscaling.max, max(v.count, 3)))
      )
    ])
    error_message = "When a pool autoscales (explicitly or by class default), count must be within [min, max]."
  }

  # GKE node pool names: 1-40 chars, lowercase alphanumeric and hyphens,
  # must start with a letter.
  validation {
    condition     = alltrue([for k, v in var.pools : can(regex("^[a-z][-a-z0-9]{0,39}$", k))])
    error_message = "Each pool name (map key) must be 1-40 characters, lowercase alphanumeric and hyphens, and begin with a letter (GKE node pool naming rule)."
  }
}

variable "class_machine_types" {
  description = "Default GCE machine type list per portable pool class. Only the first entry is used; remaining entries document an operator preference order. A pool's explicit instance_types overrides this map. When overriding this variable, all seven class keys must be supplied — partial overrides are rejected at validate time."
  type        = map(list(string))
  default = {
    system  = ["e2-standard-2", "e2-standard-4"]
    general = ["e2-standard-4", "n2-standard-4", "e2-standard-8"]
    compute = ["c2-standard-4", "c2-standard-8", "c2-standard-16"]
    memory  = ["n2-highmem-4", "n2-highmem-8"]
    storage = ["n2-standard-8", "n2-standard-16"]
    gpu     = ["g2-standard-4", "g2-standard-8"]
    arm64   = ["t2a-standard-4", "t2a-standard-8"]
  }

  validation {
    condition = alltrue([
      for c in ["system", "general", "compute", "memory", "storage", "gpu", "arm64"] :
      contains(keys(var.class_machine_types), c) && length(lookup(var.class_machine_types, c, [])) > 0
    ])
    error_message = "class_machine_types must contain a non-empty list for every pool class: system, general, compute, memory, storage, gpu, arm64."
  }
}
