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
      version = "8.8.0"
    }
  }
}

# =============================================================================
# Public Managed Zone
# =============================================================================

locals {
  # Longest context_id each name allows, after removing the characters its rule rejects.
  context_id_rules = {
    zone = { id = var.context_id, max = 63 - length("dns-") }
  }
  # Each rule's id, truncated and suffixed with a hash of the full id when longer than max.
  context_id_fit = {
    for k, r in local.context_id_rules : k => length(r.id) <= r.max ? r.id : "${substr(r.id, 0, r.max - 6)}${substr(sha256(var.context_id), 0, 6)}"
  }

  zone_name = "dns-${local.context_id_fit.zone}"
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
