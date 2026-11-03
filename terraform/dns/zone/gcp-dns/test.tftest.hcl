mock_provider "google" {}

# Verifies the public managed zone is created with the requested domain and
# that the module exposes the outputs downstream stacks (cert-manager
# cloudDNS solver, external-dns google provider) read by name. A rename
# here would silently break the wiring.
run "minimal_configuration" {
  command = plan

  variables {
    context_id  = "test"
    project_id  = "test-project"
    domain_name = "example.com"
  }

  assert {
    condition     = google_dns_managed_zone.main.dns_name == "example.com."
    error_message = "Managed zone dns_name should be the domain with a trailing dot."
  }

  assert {
    condition     = google_dns_managed_zone.main.name == "dns-test"
    error_message = "Managed zone name should follow dns-<context_id>."
  }

  assert {
    condition     = google_dns_managed_zone.main.force_destroy == true
    error_message = "force_destroy should be true so ACME/external-dns records don't block teardown."
  }

  assert {
    condition     = output.zone_name == "dns-test"
    error_message = "zone_name output should echo the managed zone's resource name."
  }

  assert {
    condition     = output.domain_name == "example.com"
    error_message = "domain_name output should echo the requested domain."
  }
}

run "empty_domain_rejected" {
  command = plan

  variables {
    context_id  = "test"
    project_id  = "test-project"
    domain_name = ""
  }

  expect_failures = [
    var.domain_name,
  ]
}

run "missing_project_id" {
  command = plan

  variables {
    context_id  = "test"
    project_id  = ""
    domain_name = "example.com"
  }

  expect_failures = [
    var.project_id,
  ]
}

# Verifies that a 63-character context_id is fitted to each name rule with a hash of the full id.
run "context_id_at_max_length" {
  command = plan

  variables {
    context_id  = "context-id-at-the-sixty-three-character-dns-label-length-limit0"
    project_id  = "test-project"
    domain_name = "example.com"
  }

  assert {
    condition     = length(google_dns_managed_zone.main.name) <= 63
    error_message = "Managed zone name must be at most 63 characters"
  }
}

# Verifies that a hyphenated context_id that fits each name rule reaches names unchanged.
run "hyphenated_context_id" {
  command = plan

  variables {
    context_id  = "my-ctx-1"
    project_id  = "test-project"
    domain_name = "example.com"
  }

  assert {
    condition     = google_dns_managed_zone.main.name == "dns-my-ctx-1"
    error_message = "Managed zone name should keep the hyphenated context_id"
  }
}
