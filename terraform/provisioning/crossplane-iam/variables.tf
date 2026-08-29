variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

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

variable "db_subnet_group_name" {
  type        = string
  description = "Name of the DB subnet group rds:CreateDBInstance references, granted alongside the instance ARN it creates."
  default     = ""
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN the rds resource type's role may use for storage encryption."
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:\\d{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN."
  }

  validation {
    condition     = var.kms_key_arn != "" || !contains(var.resources, "rds")
    error_message = "kms_key_arn is required when resources includes rds."
  }
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

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
