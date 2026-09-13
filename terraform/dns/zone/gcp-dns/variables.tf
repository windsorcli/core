#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment."
  default     = ""
}

variable "project_id" {
  type        = string
  description = "GCP project ID the managed zone is created in."
  validation {
    condition     = var.project_id != null && var.project_id != ""
    error_message = "project_id must be provided and cannot be empty."
  }
}

variable "domain_name" {
  type        = string
  description = "The fully-qualified domain name for the public managed zone (e.g. example.com)."
  validation {
    condition     = length(var.domain_name) > 0
    error_message = "domain_name must not be empty."
  }
}

variable "labels" {
  type        = map(string)
  description = "Additional labels applied to the managed zone."
  default     = {}
}

variable "enable_dnssec" {
  type        = bool
  default     = false
  description = "Enable DNSSEC signing. Operator must publish the resulting DS record at the registrar."
}
