#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "prefix" {
  description = "Prefix for the resources"
  type        = string
  default     = "windsor"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-cluster"
}

variable "kubernetes_version" {
  description = "Version of Kubernetes to use"
  type        = string
  default     = "1.32"
}

variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig is stored"
  default     = ""
}

variable "azure_use_oidc" {
  type        = bool
  description = "Whether to use OIDC for the AKS cluster"
  default     = false
}

variable "azure_client_id" {
  type        = string
  description = "Client ID for the AKS cluster"
}

variable "azure_tenant_id" {
  type        = string
  description = "Tenant ID for the AKS cluster"
}

variable "azure_subscription_id" {
  type        = string
  description = "Subscription ID for the AKS cluster"
}

variable "role_based_access_control_enabled" {
  type        = bool
  description = "Whether to enable role-based access control for the AKS cluster"
  default     = true
}
