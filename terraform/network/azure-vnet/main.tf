#---------------------------------------------------------------------------------------------------
# Versions
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.29.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Azure Provider configuration
#-----------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
  features {}
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  vnet_name = var.vnet_name == null ? "${var.name}-${var.context_id}" : var.vnet_name
  rg_name   = var.resource_group_name == null ? "${var.name}-${var.context_id}" : var.resource_group_name
  tags = merge({
    WindsorContextID = var.context_id
  }, var.tags)
}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Group
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.region
  tags = merge({
    Name = local.rg_name
  }, local.tags)
}

#-----------------------------------------------------------------------------------------------------------------------
# Virtual Network
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags = merge({
    Name = local.vnet_name
  }, local.tags)
}

#-----------------------------------------------------------------------------------------------------------------------
# Subnets
#-----------------------------------------------------------------------------------------------------------------------

# Public subnets
resource "azurerm_subnet" "public" {
  count                = length(var.vnet_subnets["public"])
  name                 = "public-${count.index + 1}-${var.context_id}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.vnet_subnets["public"][count.index]]
}

# Private subnets
resource "azurerm_subnet" "private" {
  count                = length(var.vnet_subnets["private"])
  name                 = "private-${count.index + 1}-${var.context_id}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.vnet_subnets["private"][count.index]]
}

# Isolated subnets
resource "azurerm_subnet" "isolated" {
  count                = length(var.vnet_subnets["isolated"])
  name                 = "isolated-${count.index + 1}-${var.context_id}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.vnet_subnets["isolated"][count.index]]
}

#-----------------------------------------------------------------------------------------------------------------------
# NAT Gateway
#-----------------------------------------------------------------------------------------------------------------------

# Public IP for NAT Gateway
resource "azurerm_public_ip" "nat" {
  count               = var.vnet_zones
  name                = "${var.name}-${count.index + 1}-${var.context_id}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = merge({
    Name = "${var.name}-${count.index + 1}-${var.context_id}"
  }, local.tags)
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  count               = var.vnet_zones
  name                = "${var.name}-${count.index + 1}-${var.context_id}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
  tags = merge({
    Name = "${var.name}-${count.index + 1}-${var.context_id}"
  }, local.tags)
}

# Associate public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  count                = var.vnet_zones
  nat_gateway_id       = azurerm_nat_gateway.main[count.index].id
  public_ip_address_id = azurerm_public_ip.nat[count.index].id
}

# Associate NAT Gateway with private subnet
resource "azurerm_subnet_nat_gateway_association" "private" {
  count          = var.enable_nat_gateway ? var.vnet_zones : 0
  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main[count.index].id
}
