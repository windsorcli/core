
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
  description = "CIDR block for VNET"
  type        = string
  default     = "10.20.0.0/16"
}

variable "vnet_subnets" {
  description = "Subnets to create in the VNET"
  type        = map(list(string))
  # example: {
  #   public  = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  #   private = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"] 
  #   isolated    = ["10.20.21.0/24", "10.20.22.0/24", "10.20.23.0/24"]
  # }
  default = {
    public   = []
    private  = []
    isolated = []
  }
}

# Only used if vnet_subnets is not defined
variable "vnet_zones" {
  description = "Number of availability zones to create"
  type        = number
  default     = 1
}
