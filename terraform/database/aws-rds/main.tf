#-----------------------------------------------------------------------------------------------------------------------
# Provider Configuration
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.63.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = merge(
      var.tags,
      {
        WindsorContextID = var.context_id
        ManagedBy        = "Terraform"
      }
    )
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Data
#-----------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Account's default RDS encryption key, used when manage_encryption_key is
# false and no key ARN is supplied.
data "aws_kms_key" "rds_default" {
  count  = var.manage_encryption_key || var.kms_key_arn != "" ? 0 : 1
  key_id = "alias/aws/rds"
}

#-----------------------------------------------------------------------------------------------------------------------
# KMS Key
#-----------------------------------------------------------------------------------------------------------------------

# Encryption key for RDS storage in this context, shared across every
# database, not created per instance.
resource "aws_kms_key" "rds" {
  count                   = var.manage_encryption_key && var.kms_key_arn == "" ? 1 : 0
  description             = "KMS key for RDS storage encryption in context ${var.context_id}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable IAM User Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow RDS to use the key for storage encryption",
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ],
        Resource = "*"
      }
    ]
  })
}

# AWS managed keys can't take a custom alias, so this only applies to the
# key this module creates, not the BYOK or ephemeral-default-key paths.
resource "aws_kms_alias" "rds" {
  count         = length(aws_kms_key.rds)
  name          = "alias/${var.context_id}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

#-----------------------------------------------------------------------------------------------------------------------
# Security Group
#-----------------------------------------------------------------------------------------------------------------------

# Allows Postgres access only from this cluster's own nodes, via EKS's
# auto-created cluster security group (attached to every node's primary
# ENI). The default security group (network/aws-vpc) denies all traffic.
resource "aws_security_group" "rds" {
  # checkov:skip=CKV2_AWS_5: Attached via a chart's Instance CR (vpcSecurityGroupIds), outside Terraform's own graph.
  name        = "${var.context_id}-rds"
  description = "Allow Postgres access to RDS instances in context ${var.context_id}"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
    description     = "Postgres from the cluster nodes"
  }

  tags = {
    Name = "${var.context_id}-rds"
  }
}

