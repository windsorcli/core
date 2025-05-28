#---------------------------------------------------------------------------------------------------
# Providers Configuration
# This section defines the required providers for the Terraform configuration.
# It specifies the AWS provider with a version constraint, ensuring compatibility
# with the AWS services used in this setup.
#---------------------------------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.98.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = merge(
      var.tags,
      {
        ManagedBy        = "Terraform"
        WindsorContextID = var.context_id
      }
    )
  }
}

data "aws_caller_identity" "current" {}

#---------------------------------------------------------------------------------------------------
# S3 Bucket Creation
# This section creates the S3 bucket used for storing Terraform state.
# It ensures that the bucket is unique per account and region.
#---------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  # checkov:skip=CKV2_AWS_62:Event notifications are not needed for terraform state bucket
  # checkov:skip=CKV_AWS_144:Cross-region replication is not required for Terraform state bucket
  # checkov:skip=CKV_AWS_19:Server-side encryption is configured via aws_s3_bucket_server_side_encryption_configuration
  # checkov:skip=CKV_AWS_145:KMS encryption is configured via aws_s3_bucket_server_side_encryption_configuration
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : local.default_s3_bucket_name

  tags = {
    Name = var.s3_bucket_name != "" ? var.s3_bucket_name : local.default_s3_bucket_name
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

#---------------------------------------------------------------------------------------------------
# S3 Bucket Configuration
# This section defines local variables for S3 bucket naming conventions and policy statements.
# It ensures that the bucket names are unique per account and enforces security policies
# like HTTPS and encryption for data in transit and at rest.
#---------------------------------------------------------------------------------------------------

locals {
  default_s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "terraform-state-${var.context_id}"
  kms_key_id             = var.enable_kms && var.kms_key_alias == "" ? aws_kms_key.terraform_state[0].arn : ""

  bucket_policy_statements = flatten([
    {
      Sid    = "AllowAdminAccess",
      Effect = "Allow",
      Principal = {
        AWS = concat(
          ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
          var.terraform_state_iam_roles
        )
      },
      Action = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:GetBucketLocation"
      ],
      Resource = [
        "*"
      ],
      # Resource = [
      #   aws_s3_bucket.this.arn,
      #   "${aws_s3_bucket.this.arn}/*"
      # ],
      Condition = {
        Bool = {
          "aws:SecureTransport" = "true"
        }
      }
    }
  ])

  terraform_state_kms_policy_json = var.kms_policy_override != null ? var.kms_policy_override : jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowKeyAdministration",
        Effect = "Allow",
        Principal = {
          AWS = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        },
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource = ["arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/*"],
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowKeyUsage",
        Effect = "Allow",
        Principal = {
          AWS = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = ["arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/*"],
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

#---------------------------------------------------------------------------------------------------
# Logging Configuration
# This section sets up logging for the S3 bucket. It creates a logging bucket if enabled,
# and configures the target bucket and prefix for storing access logs, which is crucial
# for monitoring and auditing access to the S3 bucket.
#---------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  count = var.s3_log_bucket_name != "" ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.s3_log_bucket_name
  target_prefix = "${aws_s3_bucket.this.id}/"
}

#---------------------------------------------------------------------------------------------------
# Encryption
# This section configures server-side encryption for the S3 bucket using either KMS or AES256.
# It ensures that all objects stored in the bucket are encrypted, enhancing data security.
#---------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms && length(aws_kms_key.terraform_state) > 0 ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms && length(aws_kms_key.terraform_state) > 0 ? aws_kms_key.terraform_state[0].arn : null
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = local.bucket_policy_statements
  })
}

#---------------------------------------------------------------------------------------------------
# Versioning
# This section enables versioning on the S3 bucket, allowing for the preservation,
# retrieval, and restoration of every version of every object stored in the bucket.
#---------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

#---------------------------------------------------------------------------------------------------
# Public Access Block
# This section configures the public access block settings for the S3 bucket,
# preventing public access to the bucket and its objects, thereby enhancing security.
#---------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#---------------------------------------------------------------------------------------------------
# DynamoDB Table for Locking
# This section creates a DynamoDB table used for state locking and consistency checking
# during Terraform operations, ensuring that only one process can modify the state at a time.
#---------------------------------------------------------------------------------------------------

resource "aws_dynamodb_table" "terraform_locks" {
  # checkov:skip=CKV_AWS_119:Encryption is not necessary for this DynamoDB table as it is used solely for Terraform state locking, which does not involve sensitive data.
  count = var.enable_dynamodb ? 1 : 0

  name         = "terraform-state-locks-${var.context_id}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

#---------------------------------------------------------------------------------------------------
# KMS Key for Terraform State Encryption (if not provided externally)
# This section creates a KMS key for encrypting the Terraform state file in S3,
# if an external KMS key is not provided. It includes key rotation and deletion settings.
#---------------------------------------------------------------------------------------------------

resource "aws_kms_key" "terraform_state" {
  count = var.enable_kms && var.kms_key_alias == "" ? 1 : 0

  description             = "KMS key for encrypting Terraform state file in S3"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = local.terraform_state_kms_policy_json
}

resource "aws_kms_alias" "terraform_state_alias" {
  count = var.enable_kms && var.kms_key_alias == "" ? 1 : 0

  name          = var.kms_key_alias != "" ? var.kms_key_alias : "alias/terraform-state-${var.context_id}"
  target_key_id = aws_kms_key.terraform_state[0].key_id
}

#---------------------------------------------------------------------------------------------------
# Backend Configuration File
# This section generates the backend configuration file for Terraform using a template.
#---------------------------------------------------------------------------------------------------

resource "local_file" "backend_config" {
  count = var.context_path != "" ? 1 : 0
  content = templatefile("${path.module}/templates/backend.tftpl", {
    bucket         = var.s3_bucket_name != "" ? var.s3_bucket_name : local.default_s3_bucket_name
    region         = var.region
    dynamodb_table = var.enable_dynamodb ? "terraform-state-locks-${var.context_id}" : ""
    kms_key_id     = var.enable_kms && var.kms_key_alias == "" ? aws_kms_key.terraform_state[0].arn : ""
  })
  filename = "${var.context_path}/terraform/backend.tf"
}
