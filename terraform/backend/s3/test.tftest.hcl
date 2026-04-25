mock_provider "aws" {}

# Mock AWS account ID for all tests
override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

# Mock the region lookup so tests don't depend on a real AWS session or the
# AWS_REGION env var. us-east-2 matches the prior module default.
override_data {
  target = data.aws_region.current
  values = {
    region = "us-east-2"
  }
}

# Verifies that the module creates resources with default naming conventions and basic configuration.
# Tests the impact of module default values in minimal configuration, including:
# - Default resource naming (S3 bucket)
# - Default security settings (encryption, public access block)
# - Default lifecycle rules
# - KMS disabled by default (SSE-S3 AES-256 only)
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "terraform-state-test"
    error_message = "Bucket name should follow default naming convention"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled by default"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "Public access should be blocked by default"
  }

  assert {
    condition     = [for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule : rule.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "aws:kms"
    error_message = "Default encryption should be SSE-KMS when enable_kms is true (the default)."
  }

  assert {
    condition     = length(aws_kms_key.terraform_state) == 1
    error_message = "KMS key should be created by default (enable_kms defaults to true)."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == true
    error_message = "force_destroy must be true unconditionally — the AWS provider reads it from state at Delete time, so it must persist from apply."
  }
}

# Verifies the SSE-S3 opt-out path: setting enable_kms = false skips the
# customer-managed KMS key entirely and configures the bucket with
# AES-256 (SSE-S3, AWS-managed keys). Useful for environments that don't
# need customer-managed keys for compliance — the bucket is still
# IAM-restricted, TLS-enforced, and encrypted at rest.
run "enable_kms_false_uses_sse_s3" {
  command = plan

  variables {
    context_id = "test"
    enable_kms = false
  }

  assert {
    condition     = length(aws_kms_key.terraform_state) == 0
    error_message = "KMS key should not be created when enable_kms is false."
  }

  assert {
    condition     = [for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule : rule.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "AES256"
    error_message = "Bucket encryption must be AES256 (SSE-S3) when enable_kms is false."
  }
}

# Lifecycle expires noncurrent versions after 90 days so destroy-time
# pagination through ListObjectVersions stays bounded. Without this,
# long-lived state buckets accumulate every apply's state write forever,
# pushing bucket-empty past the provider's retry window and surfacing as
# a BucketNotEmpty race against DeleteBucket.
run "noncurrent_versions_expire_on_90_day_lifecycle" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = length([for rule in aws_s3_bucket_lifecycle_configuration.this.rule : rule if rule.id == "expire-noncurrent-versions"]) == 1
    error_message = "A lifecycle rule named 'expire-noncurrent-versions' must be present to bound version accumulation."
  }

  assert {
    condition = length([
      for rule in aws_s3_bucket_lifecycle_configuration.this.rule :
      rule if rule.id == "expire-noncurrent-versions" && length(rule.noncurrent_version_expiration) > 0 && rule.noncurrent_version_expiration[0].noncurrent_days == 90
    ]) == 1
    error_message = "expire-noncurrent-versions rule must expire noncurrent versions after 90 days."
  }
}

# The bucket carries an explicit 30m delete timeout so a future aws
# provider version can't silently shorten it below what's needed for
# the empty-then-delete flow on a long-lived versioned bucket.
run "bucket_has_explicit_delete_timeout" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = aws_s3_bucket.this.timeouts.delete == "30m"
    error_message = "aws_s3_bucket.this must set timeouts.delete to 30m for reliable destroy on versioned buckets."
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values correctly override defaults for:
# - Resource naming
# - Security settings
# - Optional features (KMS)
# - Logging configuration
run "full_configuration" {
  command = plan

  variables {
    context_id          = "test"
    enable_kms          = true
    s3_bucket_name      = "custom-terraform-state"
    s3_log_bucket_name  = "custom-log-bucket"
    kms_key_alias       = ""
    kms_policy_override = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowKeyAdministration\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":[\"arn:aws:iam::123456789012:root\"]},\"Action\":[\"kms:*\"]}]}"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "custom-terraform-state"
    error_message = "Bucket name should match input"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 1
    error_message = "Logging should be configured when log bucket name is provided"
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "custom-log-bucket"
    error_message = "Log bucket name should match input"
  }

  assert {
    condition     = length(aws_kms_key.terraform_state) == 1
    error_message = "KMS key should be created when enabled"
  }

  assert {
    condition     = [for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule : rule.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "aws:kms"
    error_message = "Encryption should use KMS when enabled"
  }
}

# Validates that the backend configuration file is generated with correct resource names
# when a context path is provided, enabling Terraform to use the S3 backend.
# The rendered backend.tfvars must always declare use_lockfile = true so the bucket's
# own S3 object-lock takes over state locking (DynamoDB is no longer involved).
run "backend_config_generation" {
  command = apply

  variables {
    context_id   = "test"
    context_path = "test"
    enable_kms   = false
  }

  assert {
    condition     = length(local_file.backend_config) == 1
    error_message = "Backend config should be generated with context path"
  }

  assert {
    condition = trimspace(local_file.backend_config[0].content) == trimspace(<<EOF
bucket = "terraform-state-test"
region = "us-east-2"
use_lockfile = true
EOF
    )
    error_message = "Backend config should contain bucket, region, and use_lockfile = true"
  }
}

# Verifies that the backend configuration includes KMS key ID when encryption is enabled,
# allowing organizations to use their own encryption keys for enhanced security
run "backend_config_with_kms" {
  command = apply

  variables {
    context_id          = "test"
    context_path        = "test"
    enable_kms          = true
    kms_policy_override = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowKeyAdministration\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":[\"arn:aws:iam::123456789012:root\"]},\"Action\":[\"kms:*\"]}]}"
  }

  assert {
    condition     = can(regex("^bucket = \\\"terraform-state-test\\\"\\nregion = \\\"us-east-2\\\"\\nuse_lockfile = true\\nkms_key_id = \\\".*\\\"$", trimspace(local_file.backend_config[0].content)))
    error_message = "Backend config should include KMS key ID alongside use_lockfile"
  }
}

# Confirms that no backend configuration file is created when no context path is provided,
# preventing unnecessary file generation in the root directory
run "backend_config_without_context_path" {
  command = plan

  variables {
    context_id   = "test"
    context_path = ""
  }

  assert {
    condition     = length(local_file.backend_config) == 0
    error_message = "No backend config should be generated without context path"
  }
}

# Verifies that all input validation rules are enforced simultaneously, ensuring that
# invalid values for bucket names, log bucket names, and KMS key aliases are properly caught
run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
    var.s3_bucket_name,
    var.s3_log_bucket_name,
    var.kms_key_alias,
  ]
  variables {
    context_id         = "test"
    s3_bucket_name     = "a"                                                                # Too short
    s3_log_bucket_name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # Too long
    kms_key_alias      = "invalid-alias"                                                    # Invalid format
  }
}
