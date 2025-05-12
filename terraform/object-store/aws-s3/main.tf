#-----------------------------------------------------------------------------------------------------------------------
# Provider Configuration
#-----------------------------------------------------------------------------------------------------------------------
# Configure AWS provider with region and default tags for all resources.
# Default tags are applied to all resources created by this module.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.97.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# S3 Bucket Creation and Basic Configuration
#-----------------------------------------------------------------------------------------------------------------------
# Create the S3 bucket with automatic naming based on context_id.
# Configure essential bucket settings:
# - Versioning for object history
# - Server-side encryption for data at rest
# - Public access blocking for security

locals {
  bucket_name = var.bucket_name_override != null ? var.bucket_name_override : (
    "${var.bucket_name}-${var.context_id}"
  )
}

resource "aws_s3_bucket" "main" {
  bucket = local.bucket_name
}
