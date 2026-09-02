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
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Data
#-----------------------------------------------------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Group
#-----------------------------------------------------------------------------------------------------------------------

# Dedicated resource group for every Flexible Server in this context.
# crossplane-identity-azure's role assignment scopes to it, Azure's
# replacement for AWS's per-resource tag condition.
resource "azurerm_resource_group" "postgres" {
  name     = "${var.context_id}-postgres"
  location = var.region
  tags     = var.tags
}

#-----------------------------------------------------------------------------------------------------------------------
# Private DNS Zone
#-----------------------------------------------------------------------------------------------------------------------

# Flexible Server's VNet-integrated mode requires a linked private DNS
# zone for name resolution. Unlike RDS's DB subnet group, Flexible Server
# refuses to provision without one.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.context_id}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.postgres.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                 = "${var.context_id}-postgres-link"
  private_dns_zone_id  = azurerm_private_dns_zone.postgres.id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
  tags                 = var.tags
}

#-----------------------------------------------------------------------------------------------------------------------
# Network Security Group
#-----------------------------------------------------------------------------------------------------------------------

# Allows Postgres access only from the AKS node subnets. The default
# AllowVnetInBound rule (priority 65000) permits any port from the whole
# VNet. The explicit deny below overrides it for anything this NSG
# doesn't allow first.
resource "azurerm_network_security_group" "flexibleserver" {
  name                = "${var.context_id}-flexibleserver"
  location            = azurerm_resource_group.postgres.location
  resource_group_name = azurerm_resource_group.postgres.name
  tags                = var.tags

  security_rule {
    name                       = "AllowPostgresFromClusterNodes"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefixes    = var.allowed_subnet_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyOtherVnetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "flexibleserver" {
  subnet_id                 = var.flexibleserver_subnet_id
  network_security_group_id = azurerm_network_security_group.flexibleserver.id
}

#-----------------------------------------------------------------------------------------------------------------------
# Customer-Managed Key (optional)
#-----------------------------------------------------------------------------------------------------------------------

# Same BYOK precedence as database/aws-rds: an explicit key wins.
# Otherwise a dedicated Key Vault and key, unless the context is
# ephemeral. An ephemeral context uses Flexible Server's platform-managed
# encryption instead, with nothing created here. Unlike RDS, Azure needs
# no dedicated-key step for encryption at rest.
resource "azurerm_key_vault" "postgres" {
  count                      = var.manage_encryption_key && var.key_vault_key_id == "" ? 1 : 0
  name                       = replace("${var.context_id}-pg", "-", "")
  location                   = azurerm_resource_group.postgres.location
  resource_group_name        = azurerm_resource_group.postgres.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = var.tags
}

resource "azurerm_key_vault_key" "postgres" {
  count        = length(azurerm_key_vault.postgres)
  name         = "${var.context_id}-postgres"
  key_vault_id = azurerm_key_vault.postgres[0].id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  depends_on = [azurerm_role_assignment.key_vault_admin]
}

# Terraform's own identity needs Crypto Officer to create the key; the
# Flexible Server's identity (below) only ever needs to use it.
resource "azurerm_role_assignment" "key_vault_admin" {
  count                = length(azurerm_key_vault.postgres)
  scope                = azurerm_key_vault.postgres[0].id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Flexible Server's CMK access uses its own resource identity, not
# Crossplane's. crossplane-identity-azure only authenticates the pod that
# calls the ARM API to create the server.
resource "azurerm_user_assigned_identity" "flexibleserver_cmk" {
  count               = length(azurerm_key_vault.postgres)
  name                = "${var.context_id}-flexibleserver-cmk"
  resource_group_name = azurerm_resource_group.postgres.name
  location            = azurerm_resource_group.postgres.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "flexibleserver_cmk" {
  count                = length(azurerm_key_vault.postgres)
  scope                = azurerm_key_vault.postgres[0].id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.flexibleserver_cmk[0].principal_id
}
