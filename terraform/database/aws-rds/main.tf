#-----------------------------------------------------------------------------------------------------------------------
# Provider Configuration
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.58.0"
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

# Encryption key for RDS storage in this context. Shared across every
# database, not created per instance. AWS managed keys need explicit IAM
# grants from the calling role just like this one, so a dedicated CMK also
# gives rotation, audit trail, and revocation the default key can't.
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

# Allows Postgres access only from this cluster's own nodes, identified by
# EKS's auto-created cluster security group (attached to every node's
# primary ENI regardless of CNI driver, so this covers pod traffic under
# both the AWS VPC CNI and Cilium). The default security group (network/
# aws-vpc) denies all traffic, so an RDS Instance with no explicit
# vpcSecurityGroupIds is otherwise unreachable from any pod.
resource "aws_security_group" "rds" {
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

#-----------------------------------------------------------------------------------------------------------------------
# Secret Reader Role
#-----------------------------------------------------------------------------------------------------------------------

# Read-only access to the RDS-managed master password, for a namespace-agnostic
# bootstrap job to use in provisioning a scoped, least-privilege application
# credential — never the master credential itself, matching CNPG's own
# separation of its superuser and app-database secrets. Engine-agnostic like
# the KMS key: any database, however created, needs this same step.
resource "aws_iam_role" "secret_reader" {
  name = "${var.context_id}-rds-secret-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = var.cluster_arn
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.context_id}-rds-secret-reader"
  }
}

resource "aws_iam_policy" "secret_reader" {
  name        = "${var.context_id}-rds-secret-reader"
  description = "Read-only access to RDS-managed master password secrets, for provisioning scoped application credentials"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:rds!*"
      }
    ]
  })

  tags = {
    Name = "${var.context_id}-rds-secret-reader"
  }
}

resource "aws_iam_role_policy_attachment" "secret_reader" {
  policy_arn = aws_iam_policy.secret_reader.arn
  role       = aws_iam_role.secret_reader.name
}

# Fixed (namespace, service_account) pair, not per-consumer — the bootstrap
# job runs once in system-provisioning regardless of which app namespace it
# publishes the resulting credential into. Cross-namespace publication is a
# Kubernetes RBAC concern (a RoleBinding the target namespace grants), not an
# AWS IAM one, so this role never needs to change as consumers are added.
resource "aws_eks_pod_identity_association" "secret_reader" {
  cluster_name    = var.cluster_name
  namespace       = "system-provisioning"
  service_account = "rds-secret-reader"
  role_arn        = aws_iam_role.secret_reader.arn
}
