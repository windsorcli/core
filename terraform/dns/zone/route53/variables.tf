#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

variable "domain_name" {
  type        = string
  description = "The fully-qualified domain name for the public hosted zone (e.g. example.com)."
  validation {
    condition     = length(var.domain_name) > 0
    error_message = "domain_name must not be empty."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to the hosted zone."
  default     = {}
}
