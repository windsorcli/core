mock_provider "cloudflare" {}

variables {
  context_id = "test123"
}

run "lookup_zone" {
  command = plan

  variables {
    domain_name = "example.com"
  }

  assert {
    condition     = length(cloudflare_zone.this) == 0 && length(data.cloudflare_zone.this) == 1
    error_message = "The zone should be looked up, not created, by default."
  }
}

run "lookup_zone_in_account" {
  command = plan

  variables {
    domain_name = "example.com"
    account_id  = "abc123"
  }

  assert {
    condition     = data.cloudflare_zone.this[0].filter.account.id == "abc123"
    error_message = "The lookup should be limited to the account when account_id is set."
  }
}

run "create_zone" {
  command = plan

  variables {
    domain_name = "example.com"
    create_zone = true
    account_id  = "abc123"
  }

  assert {
    condition     = length(cloudflare_zone.this) == 1 && length(data.cloudflare_zone.this) == 0
    error_message = "The zone should be created and not looked up when create_zone is true."
  }

  assert {
    condition     = cloudflare_zone.this[0].name == "example.com" && cloudflare_zone.this[0].type == "full" && cloudflare_zone.this[0].account.id == "abc123"
    error_message = "The created zone should be a full zone named for domain_name in the account."
  }
}

run "create_zone_without_account" {
  command = plan

  variables {
    domain_name = "example.com"
    create_zone = true
  }

  expect_failures = [
    var.account_id,
  ]
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
