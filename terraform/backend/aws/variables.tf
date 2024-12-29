variable "context_path" {
  description = "The path to the context config directory"
  type        = string
  default     = null

  validation {
    condition     = var.context_path == null || can(regex("^/.*", var.context_path))
    error_message = "The context_path must be either 'null' or a valid directory path."
  }
}

variable "terraform_builder_policy" {
  description = "A policy document with principle-of-least-privilege permissions to execute Terraform"
  type = object({
    Version = string
    Statement = list(object({
      Sid      = string
      Effect   = string
      Action   = any
      Resource = any
    }))
  })
  default = {
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "TerraformBootstrapPolicy",
        Effect   = "Allow",
        Action   = "sts:GetCallerIdentity",
        Resource = "*"
      },
    ]
  }
}

variable "aws_endpoint_url" {
  description = "The endpoint for the AWS service, must include http or https, port is optional."
  type        = string
  validation {
    condition     = can(regex("^https?://", var.aws_endpoint_url))
    error_message = "The aws_endpoint_url must start with http:// or https://"
  }
  default = "http://aws.test:4566"
}

variable "bucket_name_override" {
  type    = string
  default = null
}

variable "dynamodb_table_name_override" {
  type    = string
  default = null
}

variable "kms_alias_name_override" {
  type    = string
  default = null
}

variable "terraform_builder_role_name_override" {
  type    = string
  default = null
}

variable "terraform_builder_policy_name_override" {
  type    = string
  default = null
}

variable "terraform_state_policy_name_override" {
  type    = string
  default = null
}
