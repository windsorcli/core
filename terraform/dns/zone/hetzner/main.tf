# The dns/zone/hetzner module creates a primary Hetzner DNS zone via the official
# hcloud provider and, when a parent zone in the same account is given, wires the
# NS delegation record in the parent so the subdomain resolves publicly without a
# manual step. external-dns and cert-manager then manage records inside the zone.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.66.1"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token != "" ? var.hcloud_token : null
}

# =============================================================================
# Zone
# =============================================================================

resource "hcloud_zone" "this" {
  name = var.domain_name
  mode = "primary"
  ttl  = var.ttl
  labels = merge(var.labels, {
    "windsorcli.dev/context-id" = var.context_id
    "windsorcli.dev/managed-by" = "windsor"
  })
}

# =============================================================================
# Delegation
# =============================================================================

# NS record in the parent zone pointing the subdomain at this zone's assigned
# Hetzner nameservers. Only created when parent_zone_name is set and the subdomain
# is exactly one label below the parent.
resource "hcloud_zone_rrset" "delegation" {
  count = var.parent_zone_name != "" ? 1 : 0

  zone = var.parent_zone_name
  name = trimsuffix(var.domain_name, ".${var.parent_zone_name}")
  type = "NS"
  ttl  = var.ttl
  records = [
    for ns in hcloud_zone.this.authoritative_nameservers.assigned : {
      value = "${trimsuffix(ns, ".")}."
    }
  ]

  # trimsuffix is a no-op when domain_name isn't under parent_zone_name, which
  # would silently create a wrong NS name in the parent zone. Fail instead.
  lifecycle {
    precondition {
      condition     = endswith(var.domain_name, ".${var.parent_zone_name}")
      error_message = "domain_name must be a subdomain of parent_zone_name to create the NS delegation."
    }
  }
}
