mock_provider "aws" {}
mock_provider "aws" {
  alias = "us_east_1"
}

# Verifies the public hosted zone is created with the requested domain name.
# Module outputs surface the expected fields — downstream stacks (cert-manager
# ACME issuer, external-dns) consume these by name, so a rename here would
# silently break the wiring.
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

  # Opt-in features default off.
  assert {
    condition     = length(aws_kms_key.dnssec) == 0 && length(aws_route53_key_signing_key.dnssec) == 0 && length(aws_route53_hosted_zone_dnssec.main) == 0
    error_message = "DNSSEC resources must not be created when enable_dnssec is false."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.query_log) == 0 && length(aws_route53_query_log.main) == 0
    error_message = "Query logging resources must not be created when enable_query_logging is false."
  }

  assert {
    condition     = output.ds_record == null
    error_message = "ds_record output must be null when DNSSEC is disabled."
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

# DNSSEC opt-in: us-east-1 KSK KMS key, key_signing_key bound to the zone,
# hosted_zone_dnssec set to SIGNING, and the ds_record output populated for
# the operator's registrar handoff.
run "dnssec_enabled" {
  command = plan

  variables {
    context_id    = "test"
    domain_name   = "example.com"
    enable_dnssec = true
  }

  assert {
    condition     = length(aws_kms_key.dnssec) == 1
    error_message = "KSK KMS key should be created when enable_dnssec is true."
  }

  assert {
    condition     = aws_kms_key.dnssec[0].customer_master_key_spec == "ECC_NIST_P256"
    error_message = "KSK KMS key must be ECC_NIST_P256 — Route53 rejects other specs."
  }

  assert {
    condition     = aws_kms_key.dnssec[0].key_usage == "SIGN_VERIFY"
    error_message = "KSK KMS key must have key_usage SIGN_VERIFY."
  }

  assert {
    condition     = length(aws_route53_key_signing_key.dnssec) == 1
    error_message = "Key signing key should be created when enable_dnssec is true."
  }

  assert {
    condition     = length(aws_route53_hosted_zone_dnssec.main) == 1
    error_message = "hosted_zone_dnssec resource should be created when enable_dnssec is true."
  }

  assert {
    condition     = aws_route53_hosted_zone_dnssec.main[0].signing_status == "SIGNING"
    error_message = "Signing status must be SIGNING for the zone to actually sign records."
  }
}

# Query logging opt-in: us-east-1 log group, resource policy granting Route53
# logs:CreateLogStream / PutLogEvents, and the query_log binding.
run "query_logging_enabled" {
  command = plan

  variables {
    context_id           = "test"
    domain_name          = "example.com"
    enable_query_logging = true
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.query_log) == 1
    error_message = "Log group should be created when enable_query_logging is true."
  }

  assert {
    condition     = aws_cloudwatch_log_group.query_log[0].name == "/aws/route53/example.com"
    error_message = "Log group name follows the /aws/route53/<domain> convention."
  }

  assert {
    condition     = aws_cloudwatch_log_group.query_log[0].retention_in_days == 30
    error_message = "Default retention is 30 days."
  }

  assert {
    condition     = length(aws_cloudwatch_log_resource_policy.query_log) == 1
    error_message = "Resource policy granting Route53 logs perms must be created."
  }

  assert {
    condition     = length(aws_route53_query_log.main) == 1
    error_message = "query_log binding must be created."
  }

  # Default: skip_destroy is off so destroy removes the query log group.
  assert {
    condition     = aws_cloudwatch_log_group.query_log[0].skip_destroy == false
    error_message = "skip_destroy must default to false so destroy cleans up the log group by default."
  }
}

# Opt-in: production contexts can flip the flag true so query logs
# survive teardown and age out via query_log_retention_days.
run "preserve_logs_opt_in" {
  command = plan

  variables {
    context_id               = "test"
    domain_name              = "example.com"
    enable_query_logging     = true
    preserve_logs_on_destroy = true
  }

  assert {
    condition     = aws_cloudwatch_log_group.query_log[0].skip_destroy == true
    error_message = "skip_destroy should flip to true when opted in."
  }
}
