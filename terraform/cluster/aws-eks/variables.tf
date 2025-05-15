
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
  # renovate: datasource=github-releases depName=kubernetes package=kubernetes/kubernetes
  default = "1.32"
  validation {
    condition     = can(regex("^1\\.\\d+\\$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in version format like '1.32'."
  }
}


variable "endpoint_public_access" {
  description = "Whether to enable public access to the EKS cluster."
  type        = bool
  default     = true
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
      instance_types = ["t3.medium"]
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
    minimum_ip_target        = 1
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
    external-dns           = {}
  }
}
