
# Variables
variable "prefix" {
  description = "Prefix for the resources"
  type        = string
  default     = "windsor"
}

variable "region" {
  description = "Region for the resources"
  type        = string
  default     = "eastus"
}

variable "zones" {
  description = "Number of availability zones to create"
  type        = number
  default     = 1
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "vpc_subnets" {
  description = "Subnets to create in the VPC"
  type        = map(list(string))
  # example: {
  #   public  = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  #   private = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"] 
  #   data    = ["10.20.21.0/24", "10.20.22.0/24", "10.20.23.0/24"]
  # }
  default = {
    public  = []
    private = []
    data    = []
  }
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
