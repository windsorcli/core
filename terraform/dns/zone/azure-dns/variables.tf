#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment."
  default     = ""
}

variable "domain_name" {
  type        = string
  description = "The fully-qualified domain name for the public DNS zone (e.g. example.com)."
  validation {
    condition     = length(var.domain_name) > 0
    error_message = "domain_name must not be empty."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Existing resource group to create the DNS zone in. Leave empty to provision a new RG named rg-dns-<context_id>."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region for the resource group. Azure DNS zones are global, but the RG itself has a region."
  default     = "eastus"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to the zone and resource group."
  default     = {}
}
