#---------------------------------------------------------------------------------------------------
# Versions
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.27.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Azure Provider configuration
#-----------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
  use_oidc        = var.azure_use_oidc
  client_id       = var.azure_client_id
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
  features {}
}

#-----------------------------------------------------------------------------------------------------------------------
# Resource Group
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-vpc-rg"
  location = "eastus"
}

#-----------------------------------------------------------------------------------------------------------------------
# Virtual Network
#-----------------------------------------------------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vpc"
  address_space       = [var.vpc_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

#-----------------------------------------------------------------------------------------------------------------------
# Subnets
#-----------------------------------------------------------------------------------------------------------------------

# Public subnets
resource "azurerm_subnet" "public" {
  count                = length(var.vpc_subnets["public"]) > 0 ? length(var.vpc_subnets["public"]) : var.zones
  name                 = "${var.prefix}-pub-subnet-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = length(var.vpc_subnets["public"]) > 0 ? [var.vpc_subnets["public"][count.index]] : ["${join(".", slice(split(".", var.vpc_cidr), 0, 2))}.${count.index + 1}.0/24"]
}

# Private subnets
resource "azurerm_subnet" "private" {
  count                = length(var.vpc_subnets["private"]) > 0 ? length(var.vpc_subnets["private"]) : var.zones
  name                 = "${var.prefix}-priv-subnet-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = length(var.vpc_subnets["private"]) > 0 ? [var.vpc_subnets["private"][count.index]] : ["${join(".", slice(split(".", var.vpc_cidr), 0, 2))}.1${count.index + 1}.0/24"]
}

# Data subnets
resource "azurerm_subnet" "data" {
  count                = length(var.vpc_subnets["data"]) > 0 ? length(var.vpc_subnets["data"]) : var.zones
  name                 = "${var.prefix}-data-subnet-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = length(var.vpc_subnets["data"]) > 0 ? [var.vpc_subnets["data"][count.index]] : ["${join(".", slice(split(".", var.vpc_cidr), 0, 2))}.2${count.index + 1}.0/24"]
}

#-----------------------------------------------------------------------------------------------------------------------
# NAT Gateway
#-----------------------------------------------------------------------------------------------------------------------

# Public IP for NAT Gateway
resource "azurerm_public_ip" "nat" {
  count               = var.zones
  name                = "${var.prefix}-nat-gw-ip-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  count               = var.zones
  name                = "${var.prefix}-nat-gw-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
}

# Associate public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  count                = var.zones
  nat_gateway_id       = azurerm_nat_gateway.main[count.index].id
  public_ip_address_id = azurerm_public_ip.nat[count.index].id
}

# Associate NAT Gateway with private subnet
resource "azurerm_subnet_nat_gateway_association" "private" {
  count          = var.zones
  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main[count.index].id
}

# Associate NAT Gateway with data subnet
resource "azurerm_subnet_nat_gateway_association" "data" {
  count          = var.zones
  subnet_id      = azurerm_subnet.data[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main[count.index].id
}
