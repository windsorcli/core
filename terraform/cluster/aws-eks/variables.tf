
#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig is stored"
  default     = ""
}

variable "cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
  default     = "windsor-core"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster name must not be empty."
  }
}

variable "kubernetes_version" {
  description = "The kubernetes version to deploy."
  type        = string
  default     = "1.32"
  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in format like '1.32'."
  }
}

variable "vpc_id" {
  description = "The ID of the VPC where the EKS cluster will be created."
  type        = string
  default     = "vpc-0c2bbc3cc4734c126"
}

variable "node_groups" {
  description = "Map of EKS managed node group definitions to create."
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = optional(number, 20)
    labels         = optional(map(string), {})
    taints         = optional(list(object({
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
