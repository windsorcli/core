#-----------------------------------------------------------------------------------------------------------------------
# Providers
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Data
#-----------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Catalog
#-----------------------------------------------------------------------------------------------------------------------

# Per-resource-type ServiceAccount, namespace, and IAM policy. Adding a new
# Crossplane-managed AWS resource type means adding an entry here.
locals {
  catalog = {
    rds = {
      namespace       = "system-provisioning"
      service_account = "provider-aws-rds"
      # Describe/List actions don't support resource-level restriction in
      # RDS's IAM action reference; scoped to db:*/snapshot:* everywhere
      # else, via the windsorcli.dev/cluster request/resource tag.
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            # CreateDBInstance also touches the DB subnet group it
            # references, not just the instance ARN it creates.
            Effect = "Allow"
            Action = "rds:CreateDBInstance"
            Resource = [
              "arn:aws:rds:*:${data.aws_caller_identity.current.account_id}:db:*",
              "arn:aws:rds:*:${data.aws_caller_identity.current.account_id}:subgrp:${var.cluster_tag}-crossplane-rds",
            ]
            Condition = {
              StringEquals = {
                "aws:RequestTag/windsorcli.dev/cluster" = var.cluster_tag
              }
            }
          },
          {
            Effect = "Allow"
            Action = [
              "rds:ModifyDBInstance",
              "rds:DeleteDBInstance",
              "rds:AddTagsToResource",
              "rds:RemoveTagsFromResource",
              "rds:CreateDBSnapshot",
            ]
            Resource = [
              "arn:aws:rds:*:${data.aws_caller_identity.current.account_id}:db:*",
              "arn:aws:rds:*:${data.aws_caller_identity.current.account_id}:snapshot:*",
            ]
            Condition = {
              StringEquals = {
                "aws:ResourceTag/windsorcli.dev/cluster" = var.cluster_tag
              }
            }
          },
          {
            Effect = "Allow"
            Action = [
              "rds:DescribeDBInstances",
              "rds:DescribeDBSnapshots",
              "rds:DescribeDBSubnetGroups",
              "rds:ListTagsForResource",
            ]
            Resource = "*"
          },
          {
            # One-time-per-account: RDS needs its service-linked role to
            # exist before it can create any DB instance.
            Effect   = "Allow"
            Action   = "iam:CreateServiceLinkedRole"
            Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"
            Condition = {
              StringLike = {
                "iam:AWSServiceName" = "rds.amazonaws.com"
              }
            }
          },
        ]
      })
    }
  }

  selected = { for r in var.resources : r => local.catalog[r] }
}

#-----------------------------------------------------------------------------------------------------------------------
# IAM Roles
#-----------------------------------------------------------------------------------------------------------------------

# The role each selected resource type's Crossplane provider pod assumes via
# EKS Pod Identity, scoped to this cluster's Pod Identity Agent.
resource "aws_iam_role" "this" {
  for_each = local.selected
  name     = "${var.cluster_name}-crossplane-${each.key}"

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
    Name = "${var.cluster_name}-crossplane-${each.key}"
  }
}

resource "aws_iam_policy" "this" {
  for_each    = local.selected
  name        = "${var.cluster_name}-crossplane-${each.key}"
  description = "IAM policy for Crossplane's provider-aws-${each.key}"
  policy      = each.value.policy

  tags = {
    Name = "${var.cluster_name}-crossplane-${each.key}"
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = local.selected
  policy_arn = aws_iam_policy.this[each.key].arn
  role       = aws_iam_role.this[each.key].name
}

resource "aws_eks_pod_identity_association" "this" {
  for_each        = local.selected
  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.this[each.key].arn
}
