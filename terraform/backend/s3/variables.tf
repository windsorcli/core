#---------------------------------------------------------------------------------------------------
# General Context
#---------------------------------------------------------------------------------------------------

variable "context_path" {
  type        = string
  description = "The path to the context folder"
  default     = ""
}

variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  default     = null
}

#---------------------------------------------------------------------------------------------------
# AWS Region
#---------------------------------------------------------------------------------------------------

variable "region" {
  description = "The AWS Region for the S3 Bucket and DynamoDB Table"
  type        = string
  default     = "us-east-2"
}

#---------------------------------------------------------------------------------------------------
# S3 Bucket
#---------------------------------------------------------------------------------------------------

variable "s3_bucket_name" {
  description = "The name of the S3 bucket for storing Terraform state, overrides the default bucket name"
  type        = string
  default     = ""
  validation {
    condition = (
      length(var.s3_bucket_name) == 0 || (
        length(var.s3_bucket_name) >= 3 &&
        length(var.s3_bucket_name) <= 63 &&
        can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.s3_bucket_name)) &&
        !can(regex("\\.\\.", var.s3_bucket_name)) &&
        !can(regex("[.-]$|^[.-]", var.s3_bucket_name))
      )
    )
    error_message = "S3 bucket name must be 3-63 characters, lowercase letters, numbers, hyphens, periods, no consecutive periods, and cannot start/end with period or hyphen."
  }
}

variable "s3_log_bucket_name" {
  description = "Name of a pre-existing, centralized S3 logging bucket to receive access logs. Must be created outside this module."
  type        = string
  default     = ""
  validation {
    condition     = length(var.s3_log_bucket_name) <= 63
    error_message = "The S3 log bucket name must be 63 characters or less."
  }
}

#---------------------------------------------------------------------------------------------------
# KMS Key
#---------------------------------------------------------------------------------------------------

variable "kms_key_alias" {
  description = "The KMS key ID for encrypting the S3 bucket"
  type        = string
  default     = ""
  validation {
    condition = (
      var.kms_key_alias == "" || can(regex("^alias\\/[a-zA-Z0-9/_-]+$", var.kms_key_alias))
    )
    error_message = "KMS key alias must be empty or match ^alias/[a-zA-Z0-9/_-]+$"
  }
}

#---------------------------------------------------------------------------------------------------
# Feature Flags
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

variable "kms_policy_override" {
  description = "Override for the KMS policy document (for testing)"
  type        = string
  default     = null
}

#---------------------------------------------------------------------------------------------------
# Tags and IAM Roles
#---------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to resources (default is empty)."
  type        = map(string)
  default     = {}
}

variable "terraform_state_iam_roles" {
  description = "List of IAM role ARNs that should have access to the Terraform state bucket"
  type        = list(string)
  default     = []
}
