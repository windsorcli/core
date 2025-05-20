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
    condition     = [for space in azurerm_virtual_network.main.address_space : space][0] == "10.0.0.0/16"
    error_message = "VNet CIDR should default to '10.0.0.0/16'"
  }

  assert {
    condition     = length(azurerm_subnet.public) == 3
    error_message = "Three public subnets should be created by default"
  }

  assert {
    condition     = length(azurerm_subnet.private) == 3
    error_message = "Three private subnets should be created by default"
  }

  assert {
    condition     = length(azurerm_subnet.isolated) == 3
    error_message = "Three isolated subnets should be created by default"
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
      public   = ["10.30.1.0/24", "10.30.2.0/24"]
      private  = ["10.30.11.0/24", "10.30.12.0/24"]
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
    condition     = tolist(azurerm_virtual_network.main.address_space)[0] == "10.30.0.0/16"
    error_message = "VNet CIDR should match input value"
  }

  assert {
    condition     = length(azurerm_subnet.public) == 2
    error_message = "Should create 2 public subnets"
  }

  assert {
    condition     = length(azurerm_subnet.private) == 2
    error_message = "Should create 2 private subnets"
  }

  assert {
    condition     = length(azurerm_subnet.isolated) == 2
    error_message = "Should create 2 isolated subnets"
  }

  assert {
    condition     = length(azurerm_nat_gateway.main) == 2
    error_message = "Two NAT Gateways should be created"
  }
}

# Tests NAT Gateway configuration
run "nat_gateway_configuration" {
  command = plan

  variables {
    context_id         = "test"
    name               = "windsor-vnet"
    enable_nat_gateway = false
  }

  assert {
    condition     = length(azurerm_subnet_nat_gateway_association.private) == 0
    error_message = "No NAT Gateway associations should be created when disabled"
  }
}

# Tests validation rules for required variables
run "multiple_invalid_inputs" {
  command = plan

  expect_failures = [
    var.context_id,
  ]

  variables {
    name = "windsor-vnet"
  }
}
