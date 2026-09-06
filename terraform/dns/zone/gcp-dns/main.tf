# The dns/zone/gcp-dns module creates a public Cloud DNS managed zone for a
# domain. It provides the authoritative public DNS for the zone, used by
# cert-manager (ACME DNS-01 challenges) and external-dns (Service / Gateway
# hostname publication). The zone name, domain, and name servers are exposed
# as outputs so downstream stacks can target the zone, and so the operator
# can configure their domain registrar's NS delegation.
#
# Kept separate from network/* so a domain can be provisioned independent
# of any cluster — useful for zone-only deployments and for cases where
# DNS infra has a different lifecycle than compute.

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.1.0"
    }
  }
}

provider "google" {}

# =============================================================================
# Public Managed Zone
# =============================================================================

locals {
  zone_name = "dns-${var.context_id}"
}

resource "google_dns_managed_zone" "main" {
  # checkov:skip=CKV_GCP_16: DNSSEC is opt-in via var.enable_dnssec, matching
  # dns/zone/route53's enable_dnssec default-off precedent.
  name        = local.zone_name
  project     = var.project_id
  dns_name    = "${var.domain_name}."
  description = "Public DNS zone for ${var.domain_name} (windsor context ${var.context_id})"
  visibility  = "public"

  # cert-manager and external-dns write ACME challenge and hostname records
  # into this zone; force_destroy clears them so the zone itself can be
  # torn down without a manual record cleanup first.
  force_destroy = true

  labels = merge({
    windsor_context_id = var.context_id
  }, var.labels)

  dnssec_config {
    state = var.enable_dnssec ? "on" : "off"
  }
}
