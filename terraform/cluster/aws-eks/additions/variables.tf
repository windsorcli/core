# =============================================================================
# Input Variables
# =============================================================================

variable "external_dns_role_arn" {
  description = "ARN of the IAM role for external-dns. If not provided, will be looked up from the cluster."
  type        = string
  default     = null
}

variable "route53_region" {
  description = "AWS region where the Route53 hosted zone is located. If not provided, will use the cluster's region."
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = ""
}

variable "context_id" {
  description = "The windsor context id for this deployment"
  type        = string
  default     = ""
}
