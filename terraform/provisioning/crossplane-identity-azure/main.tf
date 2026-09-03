#-----------------------------------------------------------------------------------------------------------------------
# Provider Configuration
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Catalog
#-----------------------------------------------------------------------------------------------------------------------

# Per-resource-type ServiceAccount, namespace, RBAC scope, and action set.
# Adding a new Crossplane-managed Azure resource type means adding an
# entry here. Same catalog shape as provisioning/crossplane-iam. Kept as
# its own module: an azurerm and an aws provider can't share one
# Terraform root.
locals {
  catalog = {
    postgres = {
      namespace       = "system-provisioning"
      service_account = "provider-azure-dbforpostgresql"
      scope           = var.postgres_resource_group_id
      actions = [
        "Microsoft.DBforPostgreSQL/flexibleServers/*",
        "Microsoft.DBforPostgreSQL/flexibleServers/databases/*",
        "Microsoft.DBforPostgreSQL/flexibleServers/configurations/*",
        # Attaching the delegated subnet and linking the private DNS zone
        # both need an explicit join/action grant. AWS's CreateDBInstance
        # needs the same: an explicit Allow on the subnet group ARN it
        # references, not just the instance ARN it creates.
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
  name                = "${var.cluster_name}-crossplane-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.region
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "this" {
  for_each                  = local.selected
  name                      = "crossplane-${each.key}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.key].id
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

#-----------------------------------------------------------------------------------------------------------------------
# RBAC
#-----------------------------------------------------------------------------------------------------------------------

# A custom role, not the built-in Contributor. Scoped to exactly the
# actions each resource type needs, at the dedicated resource group its
# own Terraform layer created. Azure's replacement for AWS's per-resource
# tag condition: Azure RBAC's ABAC condition support doesn't cover
# Microsoft.DBforPostgreSQL.
resource "azurerm_role_definition" "this" {
  for_each    = local.selected
  name        = "${var.cluster_name}-crossplane-${each.key}"
  scope       = each.value.scope
  description = "Crossplane provider-azure-${each.key} access for ${var.cluster_name}"

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
