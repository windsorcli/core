mock_provider "azurerm" {}

# Verifies that the module creates the VNet, resource group, and subnets with minimal configuration.
# Tests default values for naming, CIDR, and subnet creation.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
    name       = "windsor-vnet"
  }

  assert {
    condition     = azurerm_resource_group.main.name == "windsor-vnet-test"
    error_message = "Resource group name should follow default naming convention"
  }

  assert {
    condition     = azurerm_virtual_network.main.name == "windsor-vnet-test"
    error_message = "VNet name should follow default naming convention"
  }

  assert {
    condition     = [for space in azurerm_virtual_network.main.address_space : space][0] == "10.20.0.0/16"
    error_message = "VNet CIDR should default to '10.20.0.0/16'"
  }

  assert {
    condition     = length(azurerm_subnet.public) == 1
    error_message = "One public subnet should be created by default"
  }

  assert {
    condition     = length(azurerm_subnet.private) == 1
    error_message = "One private subnet should be created by default"
  }

  assert {
    condition     = length(azurerm_subnet.isolated) == 1
    error_message = "One isolated subnet should be created by default"
  }

  assert {
    condition     = length(azurerm_nat_gateway.main) == 1
    error_message = "One NAT Gateway should be created by default"
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values override defaults for naming, CIDR, and subnet creation.
run "full_configuration" {
  command = plan

  variables {
    region              = "westus"
    resource_group_name = "custom-rg"
    vnet_name           = "custom-vnet"
    vnet_zones          = 2
    vnet_cidr           = "10.30.0.0/16"
    vnet_subnets = {
      public  = ["10.30.1.0/24", "10.30.2.0/24"]
      private = ["10.30.11.0/24", "10.30.12.0/24"]
      isolated = ["10.30.21.0/24", "10.30.22.0/24"]
    }
    context_id = "test"
    name       = "custom"
  }

  assert {
    condition     = azurerm_resource_group.main.name == "custom-rg"
    error_message = "Resource group name should match input"
  }

  assert {
    condition     = azurerm_virtual_network.main.name == "custom-vnet"
    error_message = "VNet name should match input"
  }

  assert {
    condition     = [for space in azurerm_virtual_network.main.address_space : space][0] == "10.30.0.0/16"
    error_message = "VNet CIDR should match input"
  }

  assert {
    condition     = length(azurerm_subnet.public) == 2
    error_message = "Two public subnets should be created"
  }

  assert {
    condition     = length(azurerm_subnet.private) == 2
    error_message = "Two private subnets should be created"
  }

  assert {
    condition     = length(azurerm_subnet.isolated) == 2
    error_message = "Two isolated subnets should be created"
  }

  assert {
    condition     = length(azurerm_nat_gateway.main) == 2
    error_message = "Two NAT Gateways should be created"
  }
}
