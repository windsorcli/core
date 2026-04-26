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
  default = "1.34"
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

variable "create_cert_manager_role" {
  description = "Whether to create the IAM role, policy, and Pod Identity association for cert-manager's Route53 ACME DNS-01 solver. Enable when cert-manager will issue ACME certificates against a Route53 hosted zone in this account."
  type        = bool
  default     = false
}

variable "cert_manager_hosted_zone_ids" {
  description = "Hosted zone IDs cert-manager is allowed to write ACME challenge records to. When set, the IAM policy's Route53 record-write actions are scoped to these zones (arn:aws:route53:::hostedzone/<id>) instead of every zone in the account. Leave empty to fall back to a wildcard scope (legacy behavior)."
  type        = list(string)
  default     = []
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
  description = "Map of EKS managed node group definitions to create. Used when var.pools is empty; otherwise pools wins."
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    capacity_type  = optional(string, "ON_DEMAND")
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

  validation {
    condition = alltrue([
      for k, v in var.node_groups :
      contains(["ON_DEMAND", "SPOT", "CAPACITY_BLOCK"], v.capacity_type)
    ])
    error_message = "Each node group's capacity_type must be one of: ON_DEMAND, SPOT, CAPACITY_BLOCK."
  }
}

variable "pools" {
  description = "Portable node pool definitions, keyed by pool name. When non-empty, takes precedence over var.node_groups. Each pool maps a class (system/general/compute/memory/storage/gpu/arm64) to an EKS managed node group."
  type = map(object({
    class          = string
    count          = number
    lifecycle      = optional(string, "on-demand")
    instance_types = optional(list(string))
    root_disk_size = optional(number)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.pools : contains(
        ["system", "general", "compute", "memory", "storage", "gpu", "arm64"],
        v.class
      )
    ])
    error_message = "Each pool's class must be one of: system, general, compute, memory, storage, gpu, arm64."
  }

  validation {
    condition = alltrue([
      for k, v in var.pools :
      contains(["on-demand", "spot"], v.lifecycle)
    ])
    error_message = "Each pool's lifecycle must be 'on-demand' or 'spot'."
  }

  validation {
    condition     = alltrue([for k, v in var.pools : v.count >= 0])
    error_message = "Each pool's count must be >= 0."
  }
}

variable "class_instance_types" {
  description = "Default instance type list per portable pool class. Multi-type lists guard against single-instance-type capacity shortages. A pool's explicit instance_types overrides this map. When overriding this variable, all seven class keys must be supplied — partial overrides are rejected at validate time rather than panicking mid-plan."
  type        = map(list(string))
  default = {
    system  = ["t3.medium", "t3a.medium", "t3.large", "t3a.large"]
    general = ["t3.xlarge", "t3a.xlarge", "m5.xlarge", "m5a.xlarge"]
    compute = ["c6i.xlarge", "c6a.xlarge", "c5.xlarge"]
    memory  = ["r6i.xlarge", "r6a.xlarge", "r5.xlarge"]
    storage = ["i3.xlarge", "i4i.xlarge"]
    gpu     = ["g4dn.xlarge", "g5.xlarge"]
    arm64   = ["t4g.xlarge", "m6g.xlarge", "c6g.xlarge"]
  }

  validation {
    condition = alltrue([
      for c in ["system", "general", "compute", "memory", "storage", "gpu", "arm64"] :
      contains(keys(var.class_instance_types), c) && length(lookup(var.class_instance_types, c, [])) > 0
    ])
    error_message = "class_instance_types must contain a non-empty list for every pool class: system, general, compute, memory, storage, gpu, arm64."
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

variable "enable_ebs_encryption" {
  description = "Whether to enable EBS volume encryption for node group instances. If true and ebs_volume_kms_key_id is null, a cluster-specific KMS key will be created."
  type        = bool
  default     = true
  validation {
    condition     = !(var.enable_ebs_encryption == false && var.ebs_volume_kms_key_id != null)
    error_message = "If enable_ebs_encryption is false, ebs_volume_kms_key_id must be null."
  }
}

variable "ebs_volume_kms_key_id" {
  description = "KMS key ARN or ID to use for EBS volume encryption in node group launch templates. ARN is preferred for cross-account scenarios. If enable_ebs_encryption is true and this is null, a cluster-specific key is created."
  type        = string
  default     = null
  validation {
    condition     = var.ebs_volume_kms_key_id == null || can(regex("^(arn:aws:kms:[a-z0-9-]+:\\d{12}:key/[a-f0-9-]+|[a-f0-9-]+)$", var.ebs_volume_kms_key_id))
    error_message = "ebs_volume_kms_key_id must be a valid KMS key ARN or key ID."
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
