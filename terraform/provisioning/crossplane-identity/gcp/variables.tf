variable "project_id" {
  type        = string
  description = "GCP project ID the identities are created in"
  validation {
    condition     = var.project_id != null && var.project_id != ""
    error_message = "project_id must be provided and cannot be empty."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster, used to name each service account"
  validation {
    condition     = var.cluster_name != null && var.cluster_name != ""
    error_message = "cluster_name must be provided and cannot be empty."
  }
}

variable "resources" {
  type        = set(string)
  description = "Crossplane-managed GCP resource types to provision identity and IAM for. Supported: postgres."
  default     = []

  validation {
    condition     = alltrue([for r in var.resources : contains(["postgres"], r)])
    error_message = "resources must be a subset of: postgres."
  }
}
