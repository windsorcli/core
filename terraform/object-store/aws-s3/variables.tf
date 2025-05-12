variable "context_id" {
  description = "Context ID for resource naming"
  type        = string
}

variable "bucket_name" {
  description = "Base name for the S3 bucket (will be combined with context_id)"
  type        = string
}

variable "bucket_name_override" {
  description = "Optional override for the full bucket name (if provided, bucket_name and context_id are ignored)"
  type        = string
  default     = null
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "tags" {
  description = "Tags to apply to all resources via provider default_tags"
  type        = map(string)
  default     = {}
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "Encryption algorithm must be either AES256 or aws:kms"
  }
}

variable "kms_key_arn" {
  description = "ARN of KMS key to use for encryption (required if encryption_algorithm is aws:kms)"
  type        = string
  default     = null
}

variable "lifecycle_rules" {
  description = "List of lifecycle rules to apply to the bucket"
  type = list(object({
    id      = string
    enabled = bool
    abort_incomplete_multipart_upload_days = optional(number)
    expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })))
  }))
  default = [
    {
      id      = "default"
      enabled = true
      abort_incomplete_multipart_upload_days = 7
      expiration_days = 90
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
    }
  ]
}

variable "logging_bucket" {
  description = "Name of the bucket to send access logs to"
  type        = string
  default     = null
}

variable "versioning_enabled" {
  description = "Whether to enable versioning"
  type        = bool
  default     = true
}

variable "enforce_ssl" {
  description = "Whether to enforce SSL-only access"
  type        = bool
  default     = true
}

variable "lifecycle_rule_id" {
  description = "ID for the lifecycle rule that handles incomplete multipart uploads"
  type        = string
  default     = null
}
