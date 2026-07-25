mock_provider "hcloud" {}

variables {
  context_id = "test123"
}

run "zone_with_auto_delegation" {
  command = plan

  variables {
    domain_name      = "hetzner.windsorcli.dev"
    parent_zone_name = "windsorcli.dev"
  }

  assert {
    condition     = hcloud_zone.this.name == "hetzner.windsorcli.dev" && hcloud_zone.this.mode == "primary"
    error_message = "A primary zone should be created for domain_name."
  }

  assert {
    condition     = length(hcloud_zone_rrset.delegation) == 1
    error_message = "A delegation rrset should be created when parent_zone_name is set."
  }

  assert {
    condition     = hcloud_zone_rrset.delegation[0].zone == "windsorcli.dev" && hcloud_zone_rrset.delegation[0].name == "hetzner" && hcloud_zone_rrset.delegation[0].type == "NS"
    error_message = "Delegation should be an NS rrset named 'hetzner' in the parent zone."
  }
}

run "zone_without_delegation" {
  command = plan

  variables {
    domain_name = "hetzner.windsorcli.dev"
  }

  assert {
    condition     = length(hcloud_zone_rrset.delegation) == 0
    error_message = "No delegation rrset should be created without a parent_zone_name."
  }
}

run "invalid_domain" {
  command = plan

  variables {
    domain_name = "not a domain"
  }

  expect_failures = [
    var.domain_name,
  ]
}
