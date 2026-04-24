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

# Authoritative public zone for var.domain_name. force_destroy flips on
# during windsor destroy (TF_VAR_operation=destroy) so terraform can tear
# down the zone even with lingering records (challenges, external-dns
# entries) instead of failing the run.
resource "aws_route53_zone" "main" {
  name          = var.domain_name
  comment       = "Public DNS zone for ${var.domain_name} (windsor context ${var.context_id})"
  force_destroy = var.operation == "destroy"
}
