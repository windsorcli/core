# The dns/zone/route53 module creates a public Route53 hosted zone for a
# domain. It provides the authoritative public DNS for the zone, used by
# cert-manager (ACME DNS-01 challenges) and external-dns (Service /
# Gateway hostname publication). The hosted zone ID and name servers are
# exposed as outputs so downstream stacks can target the zone, and so
# the operator can configure their domain registrar's NS delegation.
#
# Kept separate from network/* so a domain can be provisioned independent
# of any cluster — useful for zone-only deployments and for cases where
# DNS infra has a different lifecycle than compute.

terraform {
  required_version = ">=1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.42.0"
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

# Route53 DNSSEC KSK keys and query log groups must live in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
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

data "aws_caller_identity" "current" {}

# =============================================================================
# Public Hosted Zone
# =============================================================================

# AWS provider reads force_destroy from state at Delete time, not from
# config — so this must be true at apply time, not just at destroy.
resource "aws_route53_zone" "main" {
  name          = var.domain_name
  comment       = "Public DNS zone for ${var.domain_name} (windsor context ${var.context_id})"
  force_destroy = true

  timeouts {
    delete = "15m"
  }
}

# =============================================================================
# DNSSEC (opt-in via var.enable_dnssec)
# =============================================================================

resource "aws_kms_key" "dnssec" {
  count                    = var.enable_dnssec ? 1 : 0
  provider                 = aws.us_east_1
  description              = "Route53 DNSSEC KSK for ${var.domain_name} (windsor context ${var.context_id})"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowRoute53DNSSECService"
        Effect    = "Allow"
        Principal = { Service = "dnssec-route53.amazonaws.com" }
        Action    = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
        Resource  = "*"
      },
      {
        Sid       = "AllowRoute53DNSSECCreateGrant"
        Effect    = "Allow"
        Principal = { Service = "dnssec-route53.amazonaws.com" }
        Action    = "kms:CreateGrant"
        Resource  = "*"
        Condition = {
          Bool = { "kms:GrantIsForAWSResource" = "true" }
        }
      },
    ]
  })
}

resource "aws_route53_key_signing_key" "dnssec" {
  count                      = var.enable_dnssec ? 1 : 0
  hosted_zone_id             = aws_route53_zone.main.id
  key_management_service_arn = aws_kms_key.dnssec[0].arn
  name                       = "${var.context_id}-${replace(var.domain_name, ".", "-")}-ksk"
}

resource "aws_route53_hosted_zone_dnssec" "main" {
  count          = var.enable_dnssec ? 1 : 0
  hosted_zone_id = aws_route53_key_signing_key.dnssec[0].hosted_zone_id
  signing_status = "SIGNING"
}

# =============================================================================
# Query Logging (opt-in via var.enable_query_logging)
# =============================================================================

resource "aws_cloudwatch_log_group" "query_log" {
  count             = var.enable_query_logging ? 1 : 0
  provider          = aws.us_east_1
  name              = "/aws/route53/${var.domain_name}"
  retention_in_days = var.query_log_retention_days
  skip_destroy      = var.preserve_logs_on_destroy
}

resource "aws_cloudwatch_log_resource_policy" "query_log" {
  count       = var.enable_query_logging ? 1 : 0
  provider    = aws.us_east_1
  policy_name = "route53-query-log-${var.context_id}-${replace(var.domain_name, ".", "-")}"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowRoute53QueryLogs"
        Effect    = "Allow"
        Principal = { Service = "route53.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/route53/*"
      },
    ]
  })
}

resource "aws_route53_query_log" "main" {
  count                    = var.enable_query_logging ? 1 : 0
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.query_log[0].arn
  zone_id                  = aws_route53_zone.main.id

  depends_on = [aws_cloudwatch_log_resource_policy.query_log]
}
