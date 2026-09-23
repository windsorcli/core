#-----------------------------------------------------------------------------------------------------------------------
# Provider Configuration
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Catalog
#-----------------------------------------------------------------------------------------------------------------------

# Non-null placeholder used only when operation is destroy and the sibling value is unavailable.
locals {
  resource_group_name = var.operation == "destroy" ? coalesce(var.resource_group_name, "destroy-placeholder") : var.resource_group_name
  oidc_issuer_url     = var.operation == "destroy" ? coalesce(var.oidc_issuer_url, "https://destroy-placeholder.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/") : var.oidc_issuer_url
  cluster_name        = var.operation == "destroy" ? coalesce(var.cluster_name, "destroy-placeholder") : var.cluster_name
  # A syntactically valid but non-existent Azure scope: azurerm's role
  # definition rejects an arbitrary placeholder string outright.
  postgres_resource_group_id = var.operation == "destroy" && var.postgres_resource_group_id == "" ? "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/destroy-placeholder" : var.postgres_resource_group_id
}

# Per-resource-type ServiceAccount, namespace, RBAC scope, and action set.
# Its own module: an azurerm and an aws provider can't share one root.
locals {
  catalog = {
    postgres = {
      namespace       = "system-provisioning"
      service_account = "provider-azure-dbforpostgresql"
      scope           = local.postgres_resource_group_id
      actions = [
        "Microsoft.DBforPostgreSQL/flexibleServers/*",
        "Microsoft.DBforPostgreSQL/flexibleServers/databases/*",
        "Microsoft.DBforPostgreSQL/flexibleServers/configurations/*",
        # Attaching the delegated subnet and linking the private DNS zone
        # both need an explicit join/action grant.
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/read",
        "Microsoft.Network/privateDnsZones/join/action",
        "Microsoft.Network/privateDnsZones/read",
      ]
    }
  }

  selected = { for r in var.resources : r => local.catalog[r] }
}

#-----------------------------------------------------------------------------------------------------------------------
# Identities
#-----------------------------------------------------------------------------------------------------------------------

# The identity each selected resource type's Crossplane provider pod
# authenticates as via Workload Identity.
resource "azurerm_user_assigned_identity" "this" {
  for_each            = local.selected
  name                = "${local.cluster_name}-crossplane-${each.key}"
  resource_group_name = local.resource_group_name
  location            = var.region
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "this" {
  for_each                  = local.selected
  name                      = "crossplane-${each.key}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = local.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.key].id
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

#-----------------------------------------------------------------------------------------------------------------------
# RBAC
#-----------------------------------------------------------------------------------------------------------------------

# Custom role, not Contributor: Azure RBAC's ABAC condition support
# doesn't cover Microsoft.DBforPostgreSQL.
resource "azurerm_role_definition" "this" {
  for_each    = local.selected
  name        = "${local.cluster_name}-crossplane-${each.key}"
  scope       = each.value.scope
  description = "Crossplane provider-azure-${each.key} access for ${local.cluster_name}"

  permissions {
    actions     = each.value.actions
    not_actions = []
  }

  assignable_scopes = [each.value.scope]
}

resource "azurerm_role_assignment" "this" {
  for_each           = local.selected
  scope              = each.value.scope
  role_definition_id = azurerm_role_definition.this[each.key].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.this[each.key].principal_id
}
