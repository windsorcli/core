variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
  validation {
    condition     = var.context_id != null && var.context_id != ""
    error_message = "context_id must be provided and cannot be empty."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project ID Cloud SQL is created in"
  validation {
    condition     = var.project_id != null && var.project_id != ""
    error_message = "project_id must be provided and cannot be empty."
  }
}

variable "region" {
  type        = string
  description = "GCP region for the KMS key ring"
  default     = "us-central1"
}

variable "network_id" {
  type        = string
  description = "ID of the VPC network Cloud SQL peers with for private IP connectivity. Pipe network/gcp-vpc's network_id output."
  validation {
    condition     = var.network_id != null && var.network_id != ""
    error_message = "network_id is required; pipe network/gcp-vpc's network_id output."
  }
}

variable "manage_encryption_key" {
  description = "Whether to create a dedicated KMS key ring and key for Cloud SQL storage encryption. False falls back to Cloud SQL's platform-managed encryption."
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Existing KMS CryptoKey resource name for Cloud SQL storage encryption. Set to use a key you already manage instead of one this module creates."
  type        = string
  default     = ""
}

variable "admin_credentials" {
  description = "Admin credential Secrets to create, keyed by Cloud SQL instance name. Each entry generates a random password and writes it to <key>-admin-credentials in system-database, the fixed name a chart's User CR reads via passwordSecretRef."
  type = map(object({
    username = string
  }))
  default = {}
}
