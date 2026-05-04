mock_provider "azurerm" {}

# Verifies the public DNS zone is created with the requested domain name
# and that the module exposes the outputs downstream stacks (cert-manager
# azureDNS solver, external-dns Azure provider) read by name. A rename
# here would silently break the wiring.
run "minimal_configuration" {
  command = plan

  variables {
    context_id  = "test"
    domain_name = "example.com"
  }

  assert {
    condition     = azurerm_dns_zone.main.name == "example.com"
    error_message = "DNS zone name should match the requested domain_name."
  }

  assert {
    condition     = length(azurerm_resource_group.dns) == 1
    error_message = "RG should be provisioned when resource_group_name is empty."
  }

  assert {
    condition     = azurerm_resource_group.dns[0].name == "rg-dns-test"
    error_message = "RG name should follow rg-dns-<context_id> when not overridden."
  }

  assert {
    condition     = output.zone_name == "example.com"
    error_message = "zone_name output should echo the input domain."
  }
}

run "empty_domain_rejected" {
  command = plan

  variables {
    context_id  = "test"
    domain_name = ""
  }

  expect_failures = [
    var.domain_name,
  ]
}

# When resource_group_name is supplied, the module must not create its
# own RG — it joins the existing one. Lets operators colocate the zone
# with other DNS infra they manage outside Windsor.
run "existing_resource_group" {
  command = plan

  variables {
    context_id          = "test"
    domain_name         = "example.com"
    resource_group_name = "rg-shared-dns"
  }

  assert {
    condition     = length(azurerm_resource_group.dns) == 0
    error_message = "RG should not be created when resource_group_name is supplied."
  }
}
