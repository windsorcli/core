variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
  validation {
    condition     = length(var.context_id) <= 22
    error_message = "context_id must be 22 characters or fewer; the Key Vault this module creates needs Azure's 24-character name limit for \"pg\" + context_id."
  }
}

variable "region" {
  type        = string
  description = "Azure region for the resource group and its resources"
  default     = "eastus"
}

variable "vnet_id" {
  type        = string
  description = "ID of the VNet to link the Flexible Server private DNS zone to. Pipe network/azure-vnet's vnet_id output."
  default     = null
  validation {
    condition     = var.vnet_id != null
    error_message = "vnet_id is required; pipe network/azure-vnet's vnet_id output."
  }
}

variable "flexibleserver_subnet_id" {
  type        = string
  description = "ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. Pipe network/azure-vnet's flexibleserver_subnet_id output."
  default     = null
  validation {
    condition     = var.flexibleserver_subnet_id != null
    error_message = "flexibleserver_subnet_id is required; pipe network/azure-vnet's flexibleserver_subnet_id output."
  }
}

variable "allowed_subnet_cidrs" {
  type        = list(string)
  description = "Subnet CIDRs allowed to reach Flexible Server on port 5432. Pipe network/azure-vnet's private_subnet_cidrs output (the AKS node subnets)."
  default     = []
  validation {
    condition     = length(var.allowed_subnet_cidrs) > 0
    error_message = "allowed_subnet_cidrs must not be empty; Azure rejects an NSG rule with no source address."
  }
}

variable "manage_encryption_key" {
  description = "Whether to create a dedicated Key Vault and key for Flexible Server storage encryption. False falls back to Flexible Server's platform-managed encryption."
  type        = bool
  default     = true
}

variable "key_vault_key_id" {
  description = "Existing Key Vault key ID (versionless) for Flexible Server storage encryption. Set to use a key you already manage instead of one this module creates."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
