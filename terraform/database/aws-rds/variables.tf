variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

variable "manage_encryption_key" {
  description = "Whether to create a dedicated KMS key for RDS storage encryption. False falls back to the account's AWS-managed default key."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Existing KMS key ARN for RDS storage encryption. Set to use a key you already manage instead of one this module creates."
  type        = string
  default     = ""
  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:\\d{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a valid KMS key ARN."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the secret-reader role's Pod Identity association targets."
}

variable "cluster_arn" {
  type        = string
  description = "ARN of the EKS cluster, scoping the secret-reader role's trust policy to this cluster's Pod Identity Agent."
}

variable "vpc_id" {
  description = "ID of the VPC to create the RDS security group in. Pipe network/aws-vpc's vpc_id output."
  type        = string
  default     = null
  validation {
    condition     = var.vpc_id != null
    error_message = "vpc_id is required; pipe network/aws-vpc's vpc_id output, e.g. inputs.vpc_id = terraform_output('network', 'vpc_id') in the platform-aws facet."
  }
}

variable "cluster_security_group_id" {
  description = "EKS cluster security group ID, allowed to reach RDS instances on the Postgres port. Attached to every node's ENI regardless of CNI driver. Pipe cluster/aws-eks's cluster_security_group_id output."
  type        = string
  default     = null
  validation {
    condition     = var.cluster_security_group_id != null
    error_message = "cluster_security_group_id is required; pipe cluster/aws-eks's cluster_security_group_id output, e.g. inputs.cluster_security_group_id = terraform_output('cluster', 'cluster_security_group_id') in the platform-aws facet."
  }
}

variable "kms_key_deletion_window_in_days" {
  description = "The waiting period, specified in number of days, after which the KMS key is deleted. Valid values are 7-30. Default is 7. For compliance requirements (PCI DSS, SOC 2, HIPAA), 30 days is often required for critical keys to allow time for audit and recovery."
  type        = number
  default     = 7
  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30 days."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
