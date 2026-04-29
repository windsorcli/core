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

variable "enable_dnssec" {
  type        = bool
  default     = false
  description = "Enable DNSSEC signing. Operator must publish the DS record (see ds_record output) at the registrar."
}

variable "enable_query_logging" {
  type        = bool
  default     = false
  description = "Enable Route53 query logging to a CloudWatch log group in us-east-1."
}

variable "query_log_retention_days" {
  type        = number
  default     = 30
  description = "Retention (days) for the query log group. Ignored when enable_query_logging is false."
}

variable "preserve_logs_on_destroy" {
  type        = bool
  default     = false
  description = "When true, the Route53 query log group survives terraform destroy via skip_destroy and ages out via query_log_retention_days. Recreating a zone with the same domain will fail with ResourceAlreadyExistsException unless the orphan group is imported or deleted first."
}
