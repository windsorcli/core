mock_provider "azurerm" {}

variables {
  cluster_name               = "cluster-test"
  resource_group_name        = "cluster-test-rg"
  oidc_issuer_url            = "https://eastus.oic.prod-aks.azure.com/tenant-id/oidc-id/"
  postgres_resource_group_id = "/subscriptions/sub/resourceGroups/test-postgres"
}

# Verifies no identities are created with an empty resource set.
run "no_resources_selected" {
  command = plan

  assert {
    condition     = length(azurerm_user_assigned_identity.this) == 0
    error_message = "No identities should be created when resources is empty"
  }
}

# Verifies the postgres resource type creates a correctly scoped identity,
# federated credential, and role definition.
run "postgres_selected" {
  command = plan

  variables {
    resources = ["postgres"]
  }

  assert {
    condition     = azurerm_user_assigned_identity.this["postgres"].name == "cluster-test-crossplane-postgres"
    error_message = "Identity name should follow the cluster-crossplane-<resource> convention"
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["postgres"].subject == "system:serviceaccount:system-provisioning:provider-azure-dbforpostgresql"
    error_message = "Federated credential subject should match the fixed provider-azure-dbforpostgresql ServiceAccount DeploymentRuntimeConfig pins"
  }

  assert {
    condition     = azurerm_federated_identity_credential.this["postgres"].issuer == "https://eastus.oic.prod-aks.azure.com/tenant-id/oidc-id/"
    error_message = "Federated credential should trust the supplied AKS OIDC issuer"
  }

  assert {
    condition     = contains(azurerm_role_definition.this["postgres"].permissions[0].actions, "Microsoft.DBforPostgreSQL/flexibleServers/*")
    error_message = "Role definition should include Flexible Server actions"
  }

  assert {
    condition     = contains(azurerm_role_definition.this["postgres"].permissions[0].actions, "Microsoft.Network/virtualNetworks/subnets/join/action")
    error_message = "Role definition should include the subnet join action, needed to attach the delegated subnet"
  }

  assert {
    condition     = azurerm_role_definition.this["postgres"].scope == "/subscriptions/sub/resourceGroups/test-postgres"
    error_message = "Role definition should scope to the dedicated postgres resource group, not the subscription"
  }

  assert {
    condition     = azurerm_role_assignment.this["postgres"].scope == "/subscriptions/sub/resourceGroups/test-postgres"
    error_message = "Role assignment should scope to the dedicated postgres resource group"
  }
}

# Verifies an unsupported resource type is rejected.
run "unsupported_resource_rejected" {
  command = plan

  variables {
    resources = ["storage"]
  }

  expect_failures = [var.resources]
}

# Verifies resource_group_name is required.
run "resource_group_name_required" {
  command = plan

  variables {
    resource_group_name = null
  }

  expect_failures = [var.resource_group_name]
}

# Verifies oidc_issuer_url is required.
run "oidc_issuer_url_required" {
  command = plan

  variables {
    oidc_issuer_url = null
  }

  expect_failures = [var.oidc_issuer_url]
}

# Verifies postgres without a resource group ID is rejected, rather than
# producing a role definition scoped to an empty string.
run "postgres_without_resource_group_id_rejected" {
  command = plan

  variables {
    resources                  = ["postgres"]
    postgres_resource_group_id = ""
  }

  expect_failures = [var.postgres_resource_group_id]
}
