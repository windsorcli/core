# Variables
variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  default     = null
  validation {
    condition     = var.context_id != null && var.context_id != ""
    error_message = "context_id must be provided and cannot be empty."
  }
}

variable "region" {
  description = "Region for the resources"
  type        = string
  default     = "eastus"
}

variable "name" {
  description = "Name of the resource"
  type        = string
  default     = "network"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "vnet_name" {
  description = "Name of the VNET"
  type        = string
  default     = null
}

variable "vnet_cidr" {
  description = "CIDR block for the VNET"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vnet_subnets" {
  description = "Subnets to create in the VNET"
  type        = map(list(string))
  default = {
    private  = []
    isolated = []
    public   = []
  }
  validation {
    condition     = alltrue([for subnet in var.vnet_subnets["private"] : can(cidrhost(subnet, 0))])
    error_message = "Each private subnet must be a valid CIDR block"
  }

  validation {
    condition     = alltrue([for subnet in var.vnet_subnets["isolated"] : can(cidrhost(subnet, 0))])
    error_message = "Each isolated subnet must be a valid CIDR block"
  }

  validation {
    condition     = alltrue([for subnet in var.vnet_subnets["public"] : can(cidrhost(subnet, 0))])
    error_message = "Each public subnet must be a valid CIDR block"
  }
}

variable "vnet_zones" {
  description = "Number of availability zones to create. Only used if vnet_subnets is not defined"
  type        = number
  default     = 1
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to the resources"
  type        = map(string)
  default     = {}
}
