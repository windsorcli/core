#---------------------------------------------------------------------------------------------------
# Versions
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.28.0"
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
  vnet_name = var.vnet_name == null ? "windsor-vnet-${var.context_id}" : var.vnet_name
  rg_name   = var.resource_group_name == null ? "windsor-vnet-rg-${var.context_id}" : var.resource_group_name
}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Group
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.region
}

#-----------------------------------------------------------------------------------------------------------------------
# Virtual Network
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

#-----------------------------------------------------------------------------------------------------------------------
# Subnets
#-----------------------------------------------------------------------------------------------------------------------

# Public subnets
resource "azurerm_subnet" "public" {
  count                = length(var.vnet_subnets["public"]) > 0 ? length(var.vnet_subnets["public"]) : var.vnet_zones
  name                 = "${var.context_id}-public-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = length(var.vnet_subnets["public"]) > 0 ? [var.vnet_subnets["public"][count.index]] : ["${join(".", slice(split(".", var.vnet_cidr), 0, 2))}.${count.index + 1}.0/24"]
}

# Private subnets
resource "azurerm_subnet" "private" {
  count                = length(var.vnet_subnets["private"]) > 0 ? length(var.vnet_subnets["private"]) : var.vnet_zones
  name                 = "${var.context_id}-private-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = length(var.vnet_subnets["private"]) > 0 ? [var.vnet_subnets["private"][count.index]] : ["${join(".", slice(split(".", var.vnet_cidr), 0, 2))}.1${count.index + 1}.0/24"]
}

# Data subnets
resource "azurerm_subnet" "data" {
  count                = length(var.vnet_subnets["data"]) > 0 ? length(var.vnet_subnets["data"]) : var.vnet_zones
  name                 = "${var.context_id}-data-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = length(var.vnet_subnets["data"]) > 0 ? [var.vnet_subnets["data"][count.index]] : ["${join(".", slice(split(".", var.vnet_cidr), 0, 2))}.2${count.index + 1}.0/24"]
}

#-----------------------------------------------------------------------------------------------------------------------
# NAT Gateway
#-----------------------------------------------------------------------------------------------------------------------

# Public IP for NAT Gateway
resource "azurerm_public_ip" "nat" {
  count               = var.vnet_zones
  name                = "${var.context_id}-nat-gw-ip-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  count               = var.vnet_zones
  name                = "${var.context_id}-nat-gw-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
}

# Associate public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  count                = var.vnet_zones
  nat_gateway_id       = azurerm_nat_gateway.main[count.index].id
  public_ip_address_id = azurerm_public_ip.nat[count.index].id
}

# Associate NAT Gateway with private subnet
resource "azurerm_subnet_nat_gateway_association" "private" {
  count          = var.vnet_zones
  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main[count.index].id
}

# Associate NAT Gateway with data subnet
resource "azurerm_subnet_nat_gateway_association" "data" {
  count          = var.vnet_zones
  subnet_id      = azurerm_subnet.data[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main[count.index].id
}
