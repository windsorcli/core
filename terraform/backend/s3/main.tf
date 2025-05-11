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
      version = "5.90.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = merge(
      var.tags,
      {
        ManagedBy = "Terraform"
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
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : local.default_s3_bucket_name

  tags = {
    Name = var.s3_bucket_name != "" ? var.s3_bucket_name : local.default_s3_bucket_name
  }
}

#---------------------------------------------------------------------------------------------------
# S3 Bucket Configuration
# This section defines local variables for S3 bucket naming conventions and policy statements.
# It ensures that the bucket names are unique per account and enforces security policies
# like HTTPS and encryption for data in transit and at rest.
#---------------------------------------------------------------------------------------------------

locals {
  default_s3_bucket_name  = var.s3_bucket_name != "" ? var.s3_bucket_name : "terraform-state-${var.context_id}"
  log_bucket_name         = var.s3_log_bucket_name != "" ? var.s3_log_bucket_name : (var.s3_bucket_name != "" ? "${var.s3_bucket_name}-logs" : "terraform-state-logs-${var.context_id}")

  bucket_policy_statements = flatten([
    var.bucket_policy_enforce_https ? [
      {
        Sid       = "enforceHttps",
        Effect    = "Deny",
        Principal = "*",
        Action    = "s3:*",
        Resource  = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ],
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ] : [],
    var.bucket_policy_enforce_encryption ? [
      {
        Sid       = "enforceEncryptionMethod",
        Principal = "*",
        Effect    = "Deny",
        Action    = [
          "s3:PutObject"
        ],
        Resource  = [
          "${aws_s3_bucket.this.arn}/*"
        ],
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = [
              "AES256",
              "aws:kms"
            ]
          }
        }
      }
    ] : []
  ])
}

#---------------------------------------------------------------------------------------------------
# Logging Configuration
# This section sets up logging for the S3 bucket. It creates a logging bucket if enabled,
# and configures the target bucket and prefix for storing access logs, which is crucial
# for monitoring and auditing access to the S3 bucket.
#---------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  count  = var.enable_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = aws_s3_bucket.this.id
  target_prefix = aws_s3_bucket.this.id
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
      sse_algorithm = var.enable_kms && length(aws_kms_key.terraform_state) > 0 ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms && length(aws_kms_key.terraform_state) > 0 ? aws_kms_key.terraform_state[0].arn : null
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = var.enable_bucket_policy ? 1 : 0
  bucket = aws_s3_bucket.this.id

  policy = var.custom_bucket_policy != "" ? var.custom_bucket_policy : jsonencode({
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
  count = var.enable_versioning ? 1 : 0

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

  block_public_acls       = var.public_access_block.block_public_acls
  block_public_policy     = var.public_access_block.block_public_policy
  ignore_public_acls      = var.public_access_block.ignore_public_acls
  restrict_public_buckets = var.public_access_block.restrict_public_buckets
}

#---------------------------------------------------------------------------------------------------
# DynamoDB Table for Locking
# This section creates a DynamoDB table used for state locking and consistency checking
# during Terraform operations, ensuring that only one process can modify the state at a time.
#---------------------------------------------------------------------------------------------------

resource "aws_dynamodb_table" "terraform_locks" {
  # checkov:skip=CKV_AWS_119:Encryption is not necessary for this DynamoDB table as it is used solely for Terraform state locking, which does not involve sensitive data.
  count        = var.enable_dynamodb ? 1 : 0

  name         = var.dynamodb_table_name != "" ? var.dynamodb_table_name : "terraform-state-locks-${var.context_id}"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = var.dynamodb_lock_key

  attribute {
    name = var.dynamodb_lock_key
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.dynamodb_pti_enabled
  }
}

#---------------------------------------------------------------------------------------------------
# KMS Key Policy Document for Terraform State Encryption
# This section defines the IAM policy document for the KMS key used to encrypt the Terraform state.
# It grants necessary permissions to the AWS account root user for managing the KMS key,
# while ensuring that write access is constrained to specific actions.
#---------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "terraform_state_kms_policy" {
  statement {
    sid    = "AllowKeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [ "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" ]
    }

    actions   = [
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
    ]
    resources = [ "${aws_kms_key.terraform_state[0].arn}" ]
  }

  statement {
    sid    = "AllowKeyUsage"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }

    actions   = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [ "${aws_kms_key.terraform_state[0].arn}" ]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [ "${data.aws_caller_identity.current.account_id}" ]
    }
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
  enable_key_rotation     = var.kms_enable_key_rotation
  deletion_window_in_days = var.kms_deletion_window
  policy                  = data.aws_iam_policy_document.terraform_state_kms_policy.json
}

resource "aws_kms_alias" "terraform_state_alias" {
  count = var.enable_kms && var.kms_key_alias == "" ? 1 : 0

  name          = var.kms_key_alias != "" ? var.kms_key_alias : "alias/terraform-state-${var.context_id}"
  target_key_id = aws_kms_key.terraform_state[0].key_id
}

#---------------------------------------------------------------------------------------------------
# Backend Configuration Output
# This section outputs the backend configuration to a local file in tfvars format
#---------------------------------------------------------------------------------------------------

resource "local_file" "backend_config" {
  count = 1

  content = <<EOF
bucket         = "${var.s3_bucket_name != "" ? var.s3_bucket_name : local.default_s3_bucket_name}"
region         = "${var.region}"
${var.enable_kms && length(aws_kms_key.terraform_state) > 0 ? "kms_key_id     = \"" + aws_kms_key.terraform_state[0].arn + "\"" : ""}
${var.dynamodb_table_name != "" ? "dynamodb_table = \"" + var.dynamodb_table_name + "\"" : ""}
EOF

  filename = "${var.context_path}/terraform/backend.tfvars"
}
