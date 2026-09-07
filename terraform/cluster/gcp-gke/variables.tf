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

variable "node_locations" {
  description = "Zones the cluster's own bootstrap pool and every node pool are placed in. GKE creates one instance group per zone listed here, so a fixed-count pool's node_count multiplies by length(node_locations)."
  type        = list(string)
  validation {
    condition     = length(var.node_locations) > 0
    error_message = "node_locations must contain at least one zone."
  }
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
    # n2-standard-2 (2 vCPU / 8 GB). System pool stays small — the
    # CriticalAddonsOnly taint keeps user workloads off it, this pool only
    # hosts cluster operators.
    machine_type = "n2-standard-2"
    disk_size_gb = 50
    node_count   = 1
    # GKE won't scale an idle pool up from zero on its own.
    autoscaling_enabled = false
    min_count           = 1
    max_count           = 3
  }
}

#---------------------------------------------------------------------------------------------------
# Workload Identity for cert-manager and external-dns
#---------------------------------------------------------------------------------------------------

variable "create_cert_manager_identity" {
  description = "Whether to provision a Google Service Account, Workload Identity binding, and roles/dns.admin grants for cert-manager's cloudDNS ACME DNS-01 solver. Enable when cert-manager will issue ACME certificates against a Cloud DNS zone."
  type        = bool
  default     = false
}

variable "cert_manager_dns_zone_names" {
  description = "Names of the Cloud DNS managed zones cert-manager is allowed to write ACME challenge records to. The roles/dns.admin grant is scoped to these zones — leave empty when create_cert_manager_identity is false."
  type        = list(string)
  default     = []
}

variable "create_external_dns_identity" {
  description = "Whether to provision a Google Service Account, Workload Identity binding, and roles/dns.admin grants for external-dns. Enable when external-dns will publish records to a Cloud DNS zone."
  type        = bool
  default     = true
}

variable "external_dns_dns_zone_names" {
  description = "Names of the Cloud DNS managed zones external-dns is allowed to manage records in. The roles/dns.admin grant is scoped to these zones — leave empty when create_external_dns_identity is false."
  type        = list(string)
  default     = []
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
  description = "Default GCE machine type list per portable pool class. Only the first entry is used; remaining entries document an operator preference order. A pool's explicit instance_types overrides this map. When overriding this variable, all seven class keys must be supplied — partial overrides are rejected at validate time. GCP has no leaner-memory-ratio compute family the way AWS (c6i) and Azure (Fsv2) do — C2 stays near N2's 4GB/vCPU ratio, differing instead in sustained clock speed. GCP also has no fixed storage-optimized machine family; class: storage resolves to a general-purpose machine with no local SSD attached, unlike AWS (i3/i4i) and Azure (Lsv3)."
  type        = map(list(string))
  default = {
    system  = ["n2-standard-2", "n2-standard-4"]
    general = ["n2-standard-4", "n2-standard-8"]
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
