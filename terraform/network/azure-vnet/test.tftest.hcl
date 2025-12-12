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

  assert {
    condition     = length(azurerm_route_table.private) == 1
    error_message = "One route table should be created for private subnets by default"
  }

  assert {
    condition     = length(azurerm_subnet_route_table_association.private) == 1
    error_message = "One route table association should be created for private subnets by default"
  }

  assert {
    condition     = azurerm_route_table.private[0].name == "windsor-vnet-private-1-test"
    error_message = "Route table name should follow naming convention"
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

  assert {
    condition     = length(azurerm_route_table.private) == 2
    error_message = "Two route tables should be created for private subnets"
  }

  assert {
    condition     = length(azurerm_subnet_route_table_association.private) == 2
    error_message = "Two route table associations should be created for private subnets"
  }

  assert {
    condition     = azurerm_route_table.private[0].name == "custom-private-1-test"
    error_message = "First route table name should follow naming convention"
  }

  assert {
    condition     = azurerm_route_table.private[1].name == "custom-private-2-test"
    error_message = "Second route table name should follow naming convention"
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

run "automatic_subnet_creation" {
  command = plan

  variables {
    context_id = "test"
    name       = "test-network"
    vnet_zones = 3
    vnet_subnets = {
      private  = []
      isolated = []
      public   = []
    }
  }

  assert {
    condition     = length(azurerm_subnet.private) == 3
    error_message = "Should create 3 private subnets"
  }

  assert {
    condition     = azurerm_subnet.private[0].address_prefixes[0] == "10.0.0.0/20"
    error_message = "First private subnet should be 10.0.0.0/20"
  }

  assert {
    condition     = azurerm_subnet.private[1].address_prefixes[0] == "10.0.16.0/20"
    error_message = "Second private subnet should be 10.0.16.0/20"
  }

  assert {
    condition     = azurerm_subnet.private[2].address_prefixes[0] == "10.0.32.0/20"
    error_message = "Third private subnet should be 10.0.32.0/20"
  }

  assert {
    condition     = length(azurerm_subnet.isolated) == 3
    error_message = "Should create 3 isolated subnets"
  }

  assert {
    condition     = azurerm_subnet.isolated[0].address_prefixes[0] == "10.0.48.0/24"
    error_message = "First isolated subnet should be 10.0.48.0/24"
  }

  assert {
    condition     = azurerm_subnet.isolated[1].address_prefixes[0] == "10.0.49.0/24"
    error_message = "Second isolated subnet should be 10.0.49.0/24"
  }

  assert {
    condition     = azurerm_subnet.isolated[2].address_prefixes[0] == "10.0.50.0/24"
    error_message = "Third isolated subnet should be 10.0.50.0/24"
  }

  assert {
    condition     = length(azurerm_subnet.public) == 3
    error_message = "Should create 3 public subnets"
  }

  assert {
    condition     = azurerm_subnet.public[0].address_prefixes[0] == "10.0.51.0/24"
    error_message = "First public subnet should be 10.0.51.0/24"
  }

  assert {
    condition     = azurerm_subnet.public[1].address_prefixes[0] == "10.0.52.0/24"
    error_message = "Second public subnet should be 10.0.52.0/24"
  }

  assert {
    condition     = azurerm_subnet.public[2].address_prefixes[0] == "10.0.53.0/24"
    error_message = "Third public subnet should be 10.0.53.0/24"
  }

  assert {
    condition     = length(azurerm_route_table.private) == 3
    error_message = "Three route tables should be created for private subnets when vnet_zones is 3"
  }

  assert {
    condition     = length(azurerm_subnet_route_table_association.private) == 3
    error_message = "Three route table associations should be created for private subnets when vnet_zones is 3"
  }

  assert {
    condition     = azurerm_route_table.private[0].name == "test-network-private-1-test"
    error_message = "First route table name should follow naming convention"
  }

  assert {
    condition     = azurerm_route_table.private[1].name == "test-network-private-2-test"
    error_message = "Second route table name should follow naming convention"
  }

  assert {
    condition     = azurerm_route_table.private[2].name == "test-network-private-3-test"
    error_message = "Third route table name should follow naming convention"
  }
}

# Tests validation rules for required variables
run "multiple_invalid_inputs" {
  command = plan

  variables {
    context_id = "test"
    vnet_subnets = {
      private = [
        "10.0.0.0/20",
        "invalid-cidr",
        "10.0.32.0/20"
      ]
      isolated = [
        "10.0.48.0/24",
        "10.0.49.0/24",
        "10.0.50.0/24"
      ]
      public = [
        "10.0.51.0/24",
        "10.0.52.0/24",
        "10.0.53.0/24"
      ]
    }
  }

  expect_failures = [
    var.vnet_subnets,
  ]
}
