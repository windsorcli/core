#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig is stored"
  default     = ""
}

variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

variable "cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "The kubernetes version to deploy."
  type        = string
  # renovate: datasource=github-tags depName=eks-kubernetes package=windsorcli/k8s-versions
  default = "1.33"
  validation {
    condition     = can(regex("^1\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in version format like '1.32'."
  }
}

variable "create_external_dns_role" {
  description = "Whether to create IAM role and policy for external-dns. Set to true if external-dns will be used in the cluster, even if not installed as an EKS addon."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether to enable public access to the EKS cluster."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Whether to enable private access to the EKS cluster."
  type        = bool
  default     = false
}

variable "cluster_api_access_cidr_block" {
  description = "The CIDR block for the cluster API access."
  type        = string
  default     = "0.0.0.0/0"
}

variable "vpc_id" {
  description = "The ID of the VPC where the EKS cluster will be created."
  type        = string
  default     = null
}

variable "node_groups" {
  description = "Map of EKS managed node group definitions to create."
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = optional(number, 64)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    default = {
      instance_types = ["t3.xlarge"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
}

variable "max_pods_per_node" {
  description = "Maximum number of pods that can run on a single node"
  type        = number
  default     = 64
}

variable "vpc_cni_config" {
  description = "Configuration for the VPC CNI addon"
  type = object({
    enable_prefix_delegation = bool
    warm_prefix_target       = number
    warm_ip_target           = number
    minimum_ip_target        = number
  })
  default = {
    enable_prefix_delegation = true
    warm_prefix_target       = 1
    warm_ip_target           = 1
    minimum_ip_target        = 3
  }
}

variable "fargate_profiles" {
  description = "Map of EKS Fargate profile definitions to create."
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "addons" {
  description = "Map of EKS add-ons"
  type = map(object({
    version = optional(string)
    tags    = optional(map(string), {})
  }))
  default = {
    vpc-cni                = {}
    aws-efs-csi-driver     = {}
    aws-ebs-csi-driver     = {}
    eks-pod-identity-agent = {}
    coredns                = {}
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_cloudwatch_logs" {
  description = "Whether to enable CloudWatch log group creation for EKS control plane logs"
  type        = bool
  default     = true
}

variable "enable_secrets_encryption" {
  description = "Whether to enable EKS secrets encryption at all. If false, no encryption_config is set. If true, use internal or external key."
  type        = bool
  default     = true
  validation {
    condition     = !(var.enable_secrets_encryption == false && var.secrets_encryption_kms_key_id != null)
    error_message = "If enable_secrets_encryption is false, secrets_encryption_kms_key_id must be null."
  }
}

variable "secrets_encryption_kms_key_id" {
  description = "ID of an existing KMS key to use for EKS secrets encryption. If enable_secrets_encryption is true and this is null, an internal key is created."
  type        = string
  default     = null
  validation {
    condition     = var.secrets_encryption_kms_key_id == null || can(regex("^arn:aws:kms:[a-z0-9-]+:\\d{12}:key/[a-f0-9-]+$", var.secrets_encryption_kms_key_id))
    error_message = "If secrets_encryption_kms_key_id is set, it must be a valid KMS key ARN."
  }
}
