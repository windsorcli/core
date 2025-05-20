# Variables
variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  default     = null
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
  description = "Map of subnet configurations"
  type = map(list(object({
    name             = string
    address_prefixes = list(string)
  })))
  default = {
    private = [
      {
        name             = "private-1"
        address_prefixes = ["10.0.0.0/20"] # 10.0.0.0 - 10.0.15.255
      },
      {
        name             = "private-2"
        address_prefixes = ["10.0.16.0/20"] # 10.0.16.0 - 10.0.31.255
      },
      {
        name             = "private-3"
        address_prefixes = ["10.0.32.0/20"] # 10.0.32.0 - 10.0.47.255
      }
    ]
    isolated = [
      {
        name             = "isolated-1"
        address_prefixes = ["10.0.48.0/24"] # 10.0.48.0 - 10.0.48.255
      },
      {
        name             = "isolated-2"
        address_prefixes = ["10.0.49.0/24"] # 10.0.49.0 - 10.0.49.255
      },
      {
        name             = "isolated-3"
        address_prefixes = ["10.0.50.0/24"] # 10.0.50.0 - 10.0.50.255
      }
    ]
    public = [
      {
        name             = "public-1"
        address_prefixes = ["10.0.51.0/24"] # 10.0.51.0 - 10.0.51.255
      },
      {
        name             = "public-2"
        address_prefixes = ["10.0.52.0/24"] # 10.0.52.0 - 10.0.52.255
      },
      {
        name             = "public-3"
        address_prefixes = ["10.0.53.0/24"] # 10.0.53.0 - 10.0.53.255
      }
    ]
  }
}

# Only used if vnet_subnets is not defined
variable "vnet_zones" {
  description = "Number of availability zones to create"
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
