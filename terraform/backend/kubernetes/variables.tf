#---------------------------------------------------------------------------------------------------
# State Namespace
#---------------------------------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace that holds the Terraform state Secrets."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid Kubernetes namespace name."
  }
}

#---------------------------------------------------------------------------------------------------
# Cluster Access
#---------------------------------------------------------------------------------------------------

variable "config_path" {
  description = "Path to the kubeconfig for the state cluster. Empty uses KUBE_CONFIG_PATH."
  type        = string
  default     = ""
}

variable "config_context" {
  description = "Kubeconfig context for the state cluster. Empty uses the current context."
  type        = string
  default     = ""
}
