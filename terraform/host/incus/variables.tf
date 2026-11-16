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

  validation {
    condition     = var.storage_pool_name != ""
    error_message = "storage_pool_name must not be empty."
  }
}
