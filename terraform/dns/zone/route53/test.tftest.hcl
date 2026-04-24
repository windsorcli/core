mock_provider "aws" {}

# Verifies the public hosted zone is created with the requested domain name
# and protected against teardown by default (force_destroy=false during apply).
# Also asserts the module outputs surface the expected fields — downstream
# stacks (cert-manager ACME issuer, external-dns) consume these by name, so
# a rename here would silently break the wiring.
run "minimal_configuration" {
  command = plan

  variables {
    context_id  = "test"
    domain_name = "example.com"
  }

  assert {
    condition     = aws_route53_zone.main.name == "example.com"
    error_message = "Hosted zone name should match the requested domain_name."
  }

  assert {
    condition     = aws_route53_zone.main.force_destroy == false
    error_message = "force_destroy should default to false during apply to protect the zone."
  }

  # `domain_name` is set from the input variable so it's known at plan time
  # (unlike `zone_id` and `name_servers`, which AWS computes after apply
  # and so can't be asserted in a mock_provider plan-only run). Keeping
  # this assertion still catches a rename of the output stanza.
  assert {
    condition     = output.domain_name == "example.com"
    error_message = "domain_name output should echo the input domain (downstream stacks consume this output by name)."
  }
}

# Verifies force_destroy flips on during destroy (driven by var.operation),
# matching the backend/s3 pattern.
run "force_destroy_on_destroy_operation" {
  command = plan

  variables {
    context_id  = "test"
    domain_name = "example.com"
    operation   = "destroy"
  }

  assert {
    condition     = aws_route53_zone.main.force_destroy == true
    error_message = "force_destroy must be true when operation is destroy."
  }
}

# Verifies validation: empty domain rejected, invalid operation rejected.
run "invalid_inputs_rejected" {
  command = plan

  variables {
    context_id  = "test"
    domain_name = ""
    operation   = "frobnicate"
  }

  expect_failures = [
    var.domain_name,
    var.operation,
  ]
}
