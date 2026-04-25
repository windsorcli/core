mock_provider "aws" {}

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
    condition     = aws_route53_zone.main.force_destroy == true
    error_message = "force_destroy must be true unconditionally — the AWS provider reads it from state at Delete time, so it must persist from apply."
  }

  assert {
    condition     = aws_route53_zone.main.timeouts.delete == "15m"
    error_message = "Pinned delete timeout."
  }

  # `domain_name` is set from the input variable so it's known at plan time
  # (unlike `zone_id` and `name_servers`, which AWS computes after apply).
  assert {
    condition     = output.domain_name == "example.com"
    error_message = "domain_name output should echo the input domain."
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
