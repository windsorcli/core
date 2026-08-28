variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

variable "manage_encryption_key" {
  description = "Whether to create a dedicated KMS key for RDS storage encryption. False falls back to the account's AWS-managed default key."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Existing KMS key ARN for RDS storage encryption. Set to use a key you already manage instead of one this module creates."
  type        = string
  default     = ""
  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:\\d{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a valid KMS key ARN."
  }
}

variable "kms_key_deletion_window_in_days" {
  description = "The waiting period, specified in number of days, after which the KMS key is deleted. Valid values are 7-30. Default is 7. For compliance requirements (PCI DSS, SOC 2, HIPAA), 30 days is often required for critical keys to allow time for audit and recovery."
  type        = number
  default     = 7
  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30 days."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
