# -----------------------------------------------------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------------------------------------------------

variable "remote" {
  description = "Incus client remote of the cluster. Null uses the client's default remote."
  type        = string
  default     = null
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

variable "dataset" {
  description = "ZFS dataset on every member that backs the storage pool (e.g. nvme/incus)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.:-]+(/[A-Za-z0-9_.:-]+)*$", var.dataset))
    error_message = "dataset must be a ZFS dataset path such as nvme/incus."
  }
}
