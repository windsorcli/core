# The dns/zone/cloudflare module looks up a Cloudflare zone, or creates it
# when create_zone is true. external-dns and cert-manager write records
# inside the zone. The module reads CLOUDFLARE_API_TOKEN from the environment.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }
  }
}

provider "cloudflare" {}

# =============================================================================
# Zone
# =============================================================================

# The zone is an existing Cloudflare zone, found by name.
data "cloudflare_zone" "this" {
  count = var.create_zone ? 0 : 1

  filter = {
    name    = var.domain_name
    account = var.account_id != "" ? { id = var.account_id } : null
  }
}

# The zone is a full zone owned by the account. It stays pending until the registrar delegates it.
resource "cloudflare_zone" "this" {
  count = var.create_zone ? 1 : 0

  name = var.domain_name
  type = "full"

  account = {
    id = var.account_id
  }
}
