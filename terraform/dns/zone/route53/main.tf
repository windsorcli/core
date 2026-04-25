# Public Route53 hosted zone. Kept separate from network/* so it can be
# provisioned without a cluster.

terraform {
  required_version = ">=1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.41.0"
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
