variable "context_id" {
  type        = string
  description = "The windsor context id for this deployment"
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "ID of the existing VPC"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as vpc-0a1b2c3d4e5f."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "IDs of existing subnets that serve as the public tier"
  default     = []
  validation {
    condition     = alltrue([for id in var.public_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "public_subnet_ids must contain subnet IDs such as subnet-0a1b2c3d."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of existing subnets that hold cluster nodes"
  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must name at least one subnet."
  }
  validation {
    condition     = alltrue([for id in var.private_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "private_subnet_ids must contain subnet IDs such as subnet-0a1b2c3d."
  }
}

variable "isolated_subnet_ids" {
  type        = list(string)
  description = "IDs of existing subnets that hold databases. The DB subnet group spans them when set."
  default     = []
  validation {
    condition     = alltrue([for id in var.isolated_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    error_message = "isolated_subnet_ids must contain subnet IDs such as subnet-0a1b2c3d."
  }
}

variable "private_zone_id" {
  type        = string
  description = "ID of an existing private Route53 hosted zone to pass through as private_zone_id"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for the resources this module creates"
  default     = {}
}
