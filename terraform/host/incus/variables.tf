# -----------------------------------------------------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------------------------------------------------

variable "remote" {
  description = "Incus client remote of the cluster. Null uses the client's default remote."
  type        = string
  default     = null
}

variable "members" {
  description = "Cluster members keyed by member name, with each member's storage source and network parent."
  type = map(object({
    storage_source = string
    network_parent = optional(string)
  }))

  validation {
    condition     = length(var.members) > 0
    error_message = "members must name at least one cluster member."
  }

  validation {
    condition     = alltrue([for m in values(var.members) : m.storage_source != ""])
    error_message = "Every member must set a non-empty storage_source."
  }
}

variable "storage_pool_name" {
  description = "Name of the shared storage pool."
  type        = string
  default     = "default"

  validation {
    condition     = var.storage_pool_name != ""
    error_message = "storage_pool_name must not be empty."
  }
}

variable "storage_pool_driver" {
  description = "Storage driver of the shared storage pool."
  type        = string
  default     = "zfs"

  validation {
    condition     = contains(["zfs", "lvm", "btrfs", "dir"], var.storage_pool_driver)
    error_message = "storage_pool_driver must be one of zfs, lvm, btrfs, or dir."
  }
}

variable "network_name" {
  description = "Name of the shared physical network. Null creates no network."
  type        = string
  default     = null

  validation {
    condition     = var.network_name == null || var.network_name != ""
    error_message = "network_name must not be empty."
  }

  validation {
    condition     = var.network_name == null || alltrue([for m in values(var.members) : (m.network_parent == null ? false : m.network_parent != "")])
    error_message = "Every member must set network_parent when network_name is set."
  }
}

variable "daemon_storage_pool" {
  description = "Pool that holds each member's images, backups, and logs volumes. Null leaves the server config unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.daemon_storage_pool == null || var.daemon_storage_pool != ""
    error_message = "daemon_storage_pool must not be empty."
  }
}

variable "projects" {
  description = "Projects keyed by name."
  type = map(object({
    description = optional(string)
    config      = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = !contains(keys(var.projects), "default")
    error_message = "projects must not name the default project."
  }
}

variable "certificates" {
  description = "Trusted client certificates keyed by name. A certificate that lists projects is restricted to them."
  type = map(object({
    certificate = string
    description = optional(string)
    type        = optional(string, "client")
    projects    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for c in values(var.certificates) : contains(["client", "metrics"], c.type)])
    error_message = "Every certificate type must be client or metrics."
  }

  validation {
    condition     = alltrue([for c in values(var.certificates) : startswith(trimspace(c.certificate), "-----BEGIN CERTIFICATE-----")])
    error_message = "Every certificate must be a PEM-encoded certificate."
  }
}
