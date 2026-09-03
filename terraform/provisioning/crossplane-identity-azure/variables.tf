variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

variable "region" {
  type        = string
  description = "Azure region for the identities this module creates"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group the Crossplane identities themselves are created in. Pipe cluster/azure-aks's resource_group_name output."
  default     = null
  validation {
    condition     = var.resource_group_name != null
    error_message = "resource_group_name is required; pipe cluster/azure-aks's resource_group_name output."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster, used to name each identity and role definition."
}

variable "oidc_issuer_url" {
  type        = string
  description = "AKS cluster's OIDC issuer URL, the federated credential's trust anchor. Pipe cluster/azure-aks's cluster_oidc_issuer_url output."
  default     = null
  validation {
    condition     = var.oidc_issuer_url != null
    error_message = "oidc_issuer_url is required; pipe cluster/azure-aks's cluster_oidc_issuer_url output."
  }
}

variable "postgres_resource_group_id" {
  type        = string
  description = "ID of the dedicated resource group the postgres resource type's role assignment scopes to. Required when resources includes postgres. Pipe database/azure-postgres's resource_group_id output."
  default     = ""

  validation {
    condition     = var.postgres_resource_group_id != "" || !contains(var.resources, "postgres")
    error_message = "postgres_resource_group_id is required when resources includes postgres."
  }
}

variable "resources" {
  type        = set(string)
  description = "Crossplane-managed Azure resource types to provision identity and RBAC for. Supported: postgres."
  default     = []

  validation {
    condition     = alltrue([for r in var.resources : contains(["postgres"], r)])
    error_message = "resources must be a subset of: postgres."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
