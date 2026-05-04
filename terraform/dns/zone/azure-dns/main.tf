# The dns/zone/azure-dns module creates a public Azure DNS zone for a
# domain. It provides the authoritative public DNS for the zone, used by
# cert-manager (ACME DNS-01 challenges) and external-dns (Service /
# Gateway hostname publication). The zone ID, name servers, and the
# resource group it lives in are exposed as outputs so downstream stacks
# (cert-manager, external-dns) can target the zone, and so the operator
# can configure their domain registrar's NS delegation.
#
# Kept separate from network/* so a domain can be provisioned independent
# of any cluster — useful for zone-only deployments and for cases where
# DNS infra has a different lifecycle than compute. Owns its own resource
# group so the zone's lifecycle is fully self-contained: destroying the
# stack removes both the zone and its RG without dragging unrelated
# resources with it.

terraform {
  required_version = ">=1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.71.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_subscription" "current" {}

# =============================================================================
# Resource Group
# =============================================================================

locals {
  rg_name = var.resource_group_name != "" ? var.resource_group_name : "rg-dns-${var.context_id}"
  tags = merge({
    WindsorContextID = var.context_id
    ManagedBy        = "Terraform"
  }, var.tags)
}

# Owns the DNS zone's resource group. Decoupled from the cluster RG so
# the zone can outlive the cluster (or be torn down independently).
resource "azurerm_resource_group" "dns" {
  count    = var.resource_group_name == "" ? 1 : 0
  name     = local.rg_name
  location = var.location
  tags     = local.tags
}

# Read the RG (whether created here or pre-existing) so the zone always
# has a valid scope to attach to.
data "azurerm_resource_group" "dns" {
  name       = local.rg_name
  depends_on = [azurerm_resource_group.dns]
}

# =============================================================================
# Public DNS Zone
# =============================================================================

resource "azurerm_dns_zone" "main" {
  name                = var.domain_name
  resource_group_name = data.azurerm_resource_group.dns.name
  tags                = local.tags
}
