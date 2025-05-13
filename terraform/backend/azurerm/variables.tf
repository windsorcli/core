#---------------------------------------------------------------------------------------------------
# General Context
#---------------------------------------------------------------------------------------------------

variable "context_path" {
  type        = string
  description = "The path to the context folder"
  default     = ""
}

variable "context_id" {
  description = "Context ID for the resources"
  type        = string
}

#---------------------------------------------------------------------------------------------------
# Azure Region and Resource Group
#---------------------------------------------------------------------------------------------------

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of the resource group where the storage account will be created"
  type        = string
  default     = ""
}

#---------------------------------------------------------------------------------------------------
# Storage Account
#---------------------------------------------------------------------------------------------------

variable "storage_account_name" {
  description = "Name of the storage account. If not provided, a default name will be generated"
  type        = string
  default     = ""
  validation {
    condition     = length(var.storage_account_name) <= 24
    error_message = "The storage account name must be 24 characters or less."
  }
}

variable "container_name" {
  description = "Name of the blob container for Terraform state"
  type        = string
  default     = ""
}

#---------------------------------------------------------------------------------------------------
# Tags
#---------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

#---------------------------------------------------------------------------------------------------
# Customer Managed Key (CMK) Configuration
#---------------------------------------------------------------------------------------------------

variable "enable_cmk" {
  description = "Enable Customer Managed Key encryption for the storage account"
  type        = bool
  default     = false
}

variable "key_vault_key_id" {
  description = "The ID of the Key Vault Key to use for CMK encryption"
  type        = string
  default     = ""
}
