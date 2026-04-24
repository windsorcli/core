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

variable "operation" {
  description = "Current terraform operation (\"apply\" | \"destroy\"). Set automatically by Windsor via TF_VAR_operation. Drives lifecycle behavior that can't be expressed with static lifecycle blocks (e.g. force_destroy on the hosted zone so windsor destroy can tear it down even with lingering records)."
  type        = string
  default     = "apply"
  validation {
    condition     = contains(["apply", "destroy"], var.operation)
    error_message = "operation must be either \"apply\" or \"destroy\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to the hosted zone."
  default     = {}
}
