#---------------------------------------------------------------------------------------------------
# General Context
#---------------------------------------------------------------------------------------------------

variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  validation {
    condition     = var.context_id != null && var.context_id != ""
    error_message = "context_id must be provided and cannot be empty."
  }
}

variable "region" {
  description = "GCP region for the network and its subnets"
  type        = string
  default     = "us-central1"
}

variable "zone_count" {
  description = "Number of the region's zones to expose via available_zones, for downstream node placement"
  type        = number
  default     = 3
}

variable "name" {
  description = "Name prefix for the VPC network"
  type        = string
  default     = "network"
}

variable "network_name" {
  description = "Name of the VPC network. If not provided, a default name will be generated"
  type        = string
  default     = ""
}

#---------------------------------------------------------------------------------------------------
# Subnets
#---------------------------------------------------------------------------------------------------

variable "cidr_block" {
  description = "CIDR block the subnet tiers are carved from"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR range for the public subnet. If not provided, a default range is derived from cidr_block"
  type        = string
  default     = ""
}

variable "private_subnet_cidr" {
  description = "CIDR range for the private subnet. If not provided, a default range is derived from cidr_block"
  type        = string
  default     = ""
}

variable "isolated_subnet_cidr" {
  description = "CIDR range for the isolated subnet. If not provided, a default range is derived from cidr_block"
  type        = string
  default     = ""
}

#---------------------------------------------------------------------------------------------------
# Feature Flags
#---------------------------------------------------------------------------------------------------

variable "enable_nat" {
  description = "Create a Cloud Router and Cloud NAT for the private subnet's outbound access"
  type        = bool
  default     = true
}

variable "enable_iap_ingress" {
  description = "Allow SSH/RDP ingress from Identity-Aware Proxy's fixed range"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs on every subnet"
  type        = bool
  default     = true
}
