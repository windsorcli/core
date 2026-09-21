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

variable "operation" {
  description = "Windsor-supplied operation context: \"apply\" or \"destroy\". Relaxes validation on inputs wired from sibling components, whose values are irrelevant to a delete."
  type        = string
  default     = "apply"
}

variable "network_id" {
  type        = string
  description = "ID of the VPC network Cloud SQL peers with for private IP connectivity. Pipe network/gcp-vpc's network_id output."
  default     = null
  validation {
    condition     = var.operation == "destroy" || (var.network_id != null && var.network_id != "")
    error_message = "network_id is required; pipe network/gcp-vpc's network_id output."
  }
}

variable "private_service_cidr" {
  description = "Starting address of the /16 reserved for Cloud SQL's private service connection. Must not overlap any other range in the VPC."
  type        = string
  default     = "172.28.0.0"
}

variable "manage_encryption_key" {
  description = "Whether to create a dedicated KMS key ring and key for Cloud SQL storage encryption. False falls back to Cloud SQL's platform-managed encryption."
  type        = bool
  default     = true
}

variable "key_id" {
  description = "Existing KMS CryptoKey resource name for Cloud SQL storage encryption. Set to use a key you already manage instead of one this module creates."
  type        = string
  default     = ""
}
