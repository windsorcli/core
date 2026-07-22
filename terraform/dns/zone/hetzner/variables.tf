#---------------------------------------------------------------------------------------------------
# General Context
#---------------------------------------------------------------------------------------------------

variable "context_id" {
  description = "The windsor context id for this deployment; used to label the zone."
  type        = string
  default     = ""
}

#---------------------------------------------------------------------------------------------------
# Zone
#---------------------------------------------------------------------------------------------------

variable "domain_name" {
  description = "DNS zone to create (e.g. hetzner.windsorcli.dev)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain_name))
    error_message = "domain_name must be a valid DNS hostname."
  }
}

variable "parent_zone_name" {
  description = "Parent DNS zone in the same Hetzner account to auto-create the NS delegation in (e.g. windsorcli.dev for domain_name hetzner.windsorcli.dev). Empty skips delegation (manage it manually at the registrar)."
  type        = string
  default     = ""
}

variable "ttl" {
  description = "Default TTL (seconds) for the zone and the delegation records."
  type        = number
  default     = 3600
}
