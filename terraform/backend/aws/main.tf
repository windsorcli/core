locals {
  default_tags = {
    ManagedBy  = "Terraform"
    Repository = "https://github.com/windsor-hotel/blueprints"
    Project    = "tf-backend"
  }
}

terraform {
  required_version = ">=1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.74.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = local.default_tags
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Context Data
#-----------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  is_local = data.aws_caller_identity.current.account_id == "000000000000"
}

#-----------------------------------------------------------------------------------------------------------------------
# Terraform IAM Roles
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "terraform_builder" {
  name = var.terraform_builder_role_name_override != null ? var.terraform_builder_role_name_override : format("terraform-builder-%s", random_id.postfix.hex)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.id}:root"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_builder" {
  role       = aws_iam_role.terraform_builder.name
  policy_arn = aws_iam_policy.terraform_builder.arn
}

resource "aws_iam_policy" "terraform_builder" {
  name        = var.terraform_builder_policy_name_override != null ? var.terraform_builder_policy_name_override : format("terraform-builder-%s", random_id.postfix.hex)
  description = "Terraform Builder"
  policy      = jsonencode(var.terraform_builder_policy)
}

resource "aws_iam_role_policy_attachment" "terraform_state" {
  role       = aws_iam_role.terraform_builder.name
  policy_arn = aws_iam_policy.terraform_state.arn
}

#-----------------------------------------------------------------------------------------------------------------------
# Random ID
#-----------------------------------------------------------------------------------------------------------------------

resource "random_id" "postfix" {
  byte_length = 4
}

#-----------------------------------------------------------------------------------------------------------------------
# KMS Keys
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_kms_key" "this" {
  description             = "KMS key for terraform state encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Allow root to administer key"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.id}:root"
        }
        Action = [
          "kms:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow access for Key Administrators"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.terraform_builder.arn
        }
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
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Principal = {
          AWS = aws_iam_role.terraform_builder.arn
        }
        Resource = "*"
      }
    ]
  })

}

resource "aws_kms_alias" "this" {
  name          = var.kms_alias_name_override != null ? var.kms_alias_name_override : format("alias/terraform-state-%s", random_id.postfix.hex)
  target_key_id = aws_kms_key.this.key_id
}

#-----------------------------------------------------------------------------------------------------------------------
# State Bucket
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "terraform_state" {
  #checkov:skip=CKV_AWS_144:Cross-region replication not desired at this point
  #checkov:skip=CKV2_AWS_62:Notifications for bucket activity are not desired at this point
  bucket        = var.bucket_name_override != null ? var.bucket_name_override : format("terraform-state-%s", random_id.postfix.hex)
  force_destroy = data.aws_caller_identity.current.id == "000000000000" ? true : null # for localstack
}

resource "aws_s3_bucket_logging" "terraform_state" {
  bucket        = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.terraform_state_logs.id
  target_prefix = "log/${aws_s3_bucket.terraform_state.id}/"

  depends_on = [aws_s3_bucket_acl.terraform_state_logs]
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.this.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "rule-terraform-state"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 180
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 3650
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Logging Bucket
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_state_logs" {
  #checkov:skip=CKV_AWS_144:Cross-region replication not desired at this point
  #checkov:skip=CKV2_AWS_62:Notifications for bucket activity are not desired at this point
  #checkov:skip=CKV_AWS_145:AES256 is sufficient for terraform state bucket logging
  bucket        = var.bucket_name_override != null ? var.bucket_name_override : format("terraform-state-logs-%s", random_id.postfix.hex)
  force_destroy = data.aws_caller_identity.current.id == "000000000000" ? true : null # for localstack
}

resource "aws_s3_bucket_acl" "terraform_state_logs" {
  count  = data.aws_caller_identity.current.id == "000000000000" ? 1 : 0 # for localstack
  bucket = aws_s3_bucket.terraform_state_logs.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_public_access_block" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  target_bucket = aws_s3_bucket.terraform_state_logs.id
  target_prefix = "log/${aws_s3_bucket.terraform_state_logs.id}/"

  depends_on = [aws_s3_bucket_acl.terraform_state_logs]
}

resource "aws_s3_bucket_versioning" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id
  rule {
    bucket_key_enabled = false
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "s3_logs_policy" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.terraform_state_logs.id}/*"]
  }
}

resource "aws_s3_bucket_policy" "s3_logs_bucket_policy" {
  bucket = aws_s3_bucket.terraform_state_logs.bucket
  policy = data.aws_iam_policy_document.s3_logs_policy.json
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  rule {
    id     = "terraform-state-logs"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 3650
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# DynamoDB table for Terraform state locks
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_dynamodb_table" "terraform_state_locks" {
  name         = var.dynamodb_table_name_override != null ? var.dynamodb_table_name_override : format("terraform-state-locks-%s", random_id.postfix.hex)
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.this.arn
  }

  attribute {
    name = "LockID"
    type = "S"
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Policy for working with Terraform remote state
#-----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_policy" "terraform_state" {
  name        = var.terraform_state_policy_name_override != null ? var.terraform_state_policy_name_override : format("terraform-state-%s", random_id.postfix.hex)
  path        = "/"
  description = "Allows working with Terraform state resources"

  policy = data.aws_iam_policy_document.terraform_state.json
}

data "aws_iam_policy_document" "terraform_state" {
  statement {
    sid = "S3BucketAccess"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.terraform_state.arn,
    ]
  }

  statement {
    sid = "S3ObjectAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }

  statement {
    sid = "DynamoDBAccess"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]

    resources = [
      aws_dynamodb_table.terraform_state_locks.arn,
    ]
  }

  statement {
    sid = "KMSEncryptDecrypt"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]

    resources = [
      aws_kms_key.this.arn,
    ]
  }

  statement {
    sid = "DenyNonSSLRequests"

    effect = "Deny"

    actions = [
      "s3:*",
    ]

    resources = [
      "${aws_s3_bucket.terraform_state.arn}",
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Backend Config
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # Base backend configuration
  base_backend_tfvars = <<EOF
bucket         = "${aws_s3_bucket.terraform_state.id}"
region         = "${data.aws_region.current.name}"
kms_key_id     = "${aws_kms_alias.this.name}"
dynamodb_table = "${aws_dynamodb_table.terraform_state_locks.name}"
EOF

  # Additional local-specific configuration
  local_additional_tfvars = <<EOF
endpoint          = "${replace(replace(var.aws_endpoint_url, "http://", "http://s3.${data.aws_region.current.name}."), "https://", "https://s3.${data.aws_region.current.name}.")}"
iam_endpoint      = "${var.aws_endpoint_url}"
sts_endpoint      = "${var.aws_endpoint_url}"
dynamodb_endpoint = "${var.aws_endpoint_url}"
EOF

  # Combined configuration
  backend_tfvars = local.is_local ? "${local.base_backend_tfvars}\n${local.local_additional_tfvars}" : local.base_backend_tfvars
}

resource "local_file" "backend_tfvars_file" {
  count = var.context_path != null ? 1 : 0

  content  = local.backend_tfvars
  filename = "${var.context_path}/backend.tfvars"
}
