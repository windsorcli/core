#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

variable "name" {
  description = "Name prefix for all resources in the VPC"
  type        = string
  default     = ""
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Number of availability zones to use for the subnets"
  type        = number
  default     = 3
}

variable "subnet_newbits" {
  description = "Number of new bits for the subnet"
  type        = number
  default     = 4
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable flow logs for the VPC"
  type        = bool
  default     = true
}

variable "create_flow_logs_kms_key" {
  description = "Create a KMS key for flow logs"
  type        = bool
  default     = true
}

variable "flow_logs_kms_key_id" {
  description = "The KMS key ID for flow logs"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "domain_name" {
  description = "The domain name for the Route53 hosted zone"
  type        = string
  default     = null
}
