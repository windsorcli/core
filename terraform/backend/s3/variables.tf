variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig and talosconfig are stored"
  default     = ""
}

variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  default     = null
}

#---------------------------------------------------------------------------------------------------
# AWS Account Details
#---------------------------------------------------------------------------------------------------

variable "region" {
  description = "The AWS Region for the S3 Bucket and DynamoDB Table"
  type        = string
  default     = "us-east-1"
}

#---------------------------------------------------------------------------------------------------
# S3 Bucket Configuration
#---------------------------------------------------------------------------------------------------

variable "s3_bucket_name" {
  description = "The name of the S3 bucket for storing Terraform state"
  type        = string
  default     = ""
  validation {
    condition     = length(var.s3_bucket_name) <= 63
    error_message = "The S3 bucket name must be 63 characters or less."
  }
}

variable "s3_log_bucket_name" {
  description = "Optional S3 logging bucket name override. If not provided, a name will be generated."
  type        = string
  default     = ""
  validation {
    condition     = length(var.s3_log_bucket_name) <= 63
    error_message = "The S3 log bucket name must be 63 characters or less."
  }
}

#---------------------------------------------------------------------------------------------------
# DynamoDB Table for Locking
#---------------------------------------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "The name of the DynamoDB table for state locking"
  type        = string
  default     = ""
  validation {
    condition     = length(var.dynamodb_table_name) <= 255
    error_message = "The DynamoDB table name must be 255 characters or less."
  }
}

variable "dynamodb_lock_key" {
  description = "The hash key attribute name for the DynamoDB state locking table"
  type        = string
  default     = "LockID"
}

variable "dynamodb_billing_mode" {
  description = "Billing mode for the DynamoDB table used for state locking"
  type        = string
  default     = "PAY_PER_REQUEST"
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "The billing mode must be either 'PROVISIONED' or 'PAY_PER_REQUEST'."
  }
}

variable "dynamodb_pti_enabled" {
  description = "Enable point in time recovery for the DynamoDB table"
  type        = bool
  default     = true
}

#---------------------------------------------------------------------------------------------------
# KMS Key
#---------------------------------------------------------------------------------------------------

variable "kms_key_alias" {
  description = "The KMS key ID for encrypting the S3 bucket"
  type        = string
  default     = ""
}

variable "kms_deletion_window" {
  description = "Deletion window (in days) for the KMS key"
  type        = number
  default     = 10
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "The KMS deletion window must be between 7 and 30 days."
  }
}

variable "kms_enable_key_rotation" {
  description = "Flag to enable automatic key rotation for the KMS key"
  type        = bool
  default     = true
}

#---------------------------------------------------------------------------------------------------
# S3 Bucket Policies and Versioning
#---------------------------------------------------------------------------------------------------

variable "enable_bucket_policy" {
  description = "Flag to enable the S3 bucket policy"
  type        = bool
  default     = true
}

variable "bucket_policy_enforce_https" {
  description = "Whether to include the HTTPS enforcement in the bucket policy"
  type        = bool
  default     = true
}

variable "bucket_policy_enforce_encryption" {
  description = "Whether to enforce server side encryption in the bucket policy"
  type        = bool
  default     = true
}

variable "custom_bucket_policy" {
  description = "If provided, overrides the default computed S3 bucket policy."
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Flag to enable bucket versioning on the S3 state bucket"
  type        = bool
  default     = true
}

#---------------------------------------------------------------------------------------------------
# Public Access Block
#---------------------------------------------------------------------------------------------------

variable "public_access_block" {
  description = "Public access block configuration for the S3 bucket"
  type = object({
    block_public_acls       : bool,
    block_public_policy     : bool,
    ignore_public_acls      : bool,
    restrict_public_buckets : bool,
  })
  default = {
    block_public_acls       = true,
    block_public_policy     = true,
    ignore_public_acls      = true,
    restrict_public_buckets = true
  }
}

#---------------------------------------------------------------------------------------------------
# Feature Flags and Tags
#---------------------------------------------------------------------------------------------------

variable "enable_dynamodb" {
  description = "Feature flag to enable DynamoDB table creation"
  type        = bool
  default     = true
}

variable "enable_kms" {
  description = "Feature flag to enable KMS encryption"
  type        = bool
  default     = true
}

variable "enable_log_bucket" {
  description = "Feature flag to enable log bucket creation"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources (default is empty)."
  type        = map(string)
  default     = {}
}
