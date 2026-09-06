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
  validation {
    condition     = var.context_id != null && var.context_id != ""
    error_message = "context_id must be provided and cannot be empty."
  }
}

#---------------------------------------------------------------------------------------------------
# GCS Bucket
#---------------------------------------------------------------------------------------------------

variable "location" {
  description = "GCS bucket location for storing Terraform state"
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "Name of the GCS bucket for storing Terraform state. If not provided, a default name will be generated"
  type        = string
  default     = ""
  validation {
    condition = (
      var.bucket_name == "" || (
        length(var.bucket_name) >= 3 &&
        length(var.bucket_name) <= 63 &&
        can(regex("^[a-z0-9][a-z0-9._-]*[a-z0-9]$", var.bucket_name))
      )
    )
    error_message = "GCS bucket name must be 3-63 characters, lowercase letters, numbers, hyphens, underscores, and periods, and must start and end with a letter or number."
  }
}

variable "prefix" {
  description = "Object name prefix under which Terraform state is stored in the bucket"
  type        = string
  default     = "terraform/state"
}

variable "log_bucket_name" {
  description = "Name of a pre-existing, centralized GCS logging bucket to receive access logs. Must be created outside this module."
  type        = string
  default     = ""
}

#---------------------------------------------------------------------------------------------------
# Labels
#---------------------------------------------------------------------------------------------------

variable "labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
}

#---------------------------------------------------------------------------------------------------
# Bucket IAM
#---------------------------------------------------------------------------------------------------

variable "terraform_state_principals" {
  description = "IAM members (e.g. \"user:you@example.com\", \"serviceAccount:sa@project.iam.gserviceaccount.com\") granted least-privilege access to read and write Terraform state objects in the bucket"
  type        = list(string)
  default     = []
}

#---------------------------------------------------------------------------------------------------
# Customer-Managed Encryption Key (CMEK)
#---------------------------------------------------------------------------------------------------

variable "enable_cmek" {
  description = "Encrypt the state bucket with a customer-managed KMS key instead of Google-managed encryption"
  type        = bool
  default     = false
}
