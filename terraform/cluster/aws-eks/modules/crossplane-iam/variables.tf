variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the Pod Identity associations target."
}

variable "cluster_arn" {
  type        = string
  description = "ARN of the EKS cluster, scoping each role's trust policy to this cluster's Pod Identity Agent."
}

variable "cluster_tag" {
  type        = string
  description = "Value for the windsorcli.dev/cluster tag condition scoping each resource type's IAM policy."
}

variable "resources" {
  type        = set(string)
  description = "Crossplane-managed AWS resource types to provision IAM and Pod Identity for. Supported: rds."
  default     = []

  validation {
    condition     = alltrue([for r in var.resources : contains(["rds"], r)])
    error_message = "resources must be a subset of: rds."
  }
}
