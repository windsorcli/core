#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_id" {
  description = "The windsor context id for this deployment."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Name of the Cloudflare zone, for example example.com."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain_name))
    error_message = "domain_name must be a valid DNS hostname."
  }
}

variable "create_zone" {
  description = "Create the zone. False looks up an existing zone."
  type        = bool
  default     = false
}

variable "account_id" {
  description = "Cloudflare account that owns the zone. Required when create_zone is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.create_zone || trimspace(var.account_id) != ""
    error_message = "account_id must not be empty when create_zone is true."
  }
}
