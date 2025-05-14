mock_provider "aws" {}

# Mock AWS account ID for all tests
override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

# Verifies that the module creates resources with default naming conventions and basic configuration.
# Tests the impact of module default values in minimal configuration, including:
# - Default resource naming (S3 bucket)
# - Default security settings (encryption, public access block)
# - Default lifecycle rules
# - Optional features disabled by default (DynamoDB, KMS)
run "minimal_configuration" {
  command = plan

  variables {
    context_id      = "test"
    enable_dynamodb = false
    enable_kms      = false
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
    condition     = [for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule : rule.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "AES256"
    error_message = "Default encryption should be AES256 when KMS is disabled"
  }

  assert {
    condition     = length(aws_dynamodb_table.terraform_locks) == 0
    error_message = "DynamoDB table should not be created by default"
  }

  assert {
    condition     = length(aws_kms_key.terraform_state) == 0
    error_message = "KMS key should not be created by default"
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values correctly override defaults for:
# - Resource naming
# - Security settings
# - Optional features (DynamoDB, KMS)
# - Logging configuration
run "full_configuration" {
  command = plan

  variables {
    context_id          = "test"
    enable_dynamodb     = true
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
    condition     = length(aws_dynamodb_table.terraform_locks) == 1
    error_message = "DynamoDB table should be created when enabled"
  }

  assert {
    condition     = aws_dynamodb_table.terraform_locks[0].name == "terraform-state-locks-test"
    error_message = "DynamoDB table name should follow naming convention"
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
# when a context path is provided, enabling Terraform to use the S3 backend
run "backend_config_generation" {
  command = apply

  variables {
    context_id      = "test"
    context_path    = "test"
    enable_dynamodb = false
    enable_kms      = false
  }

  assert {
    condition     = length(local_file.backend_config) == 1
    error_message = "Backend config should be generated with context path"
  }

  assert {
    condition = trimspace(local_file.backend_config[0].content) == trimspace(<<EOF
bucket = "terraform-state-test"
region = "us-east-2"
EOF
    )
    error_message = "Backend config should contain correct bucket and region"
  }
}

# Tests the backend configuration when DynamoDB state locking is enabled,
# ensuring that the state can be safely locked during operations
run "backend_config_with_dynamodb" {
  command = apply

  variables {
    context_id      = "test"
    context_path    = "test"
    enable_dynamodb = true
    enable_kms      = false
  }

  assert {
    condition     = length(local_file.backend_config) == 1
    error_message = "Backend config should be generated with context path"
  }

  assert {
    condition = trimspace(local_file.backend_config[0].content) == trimspace(<<EOF
bucket = "terraform-state-test"
region = "us-east-2"
dynamodb_table = "terraform-state-locks-test"
EOF
    )
    error_message = "Backend config should include DynamoDB table"
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
    condition     = can(regex("^bucket = \\\"terraform-state-test\\\"\\nregion = \\\"us-east-2\\\"\\ndynamodb_table = \\\"terraform-state-locks-test\\\"\\nkms_key_id = \\\".*\\\"$", trimspace(local_file.backend_config[0].content)))
    error_message = "Backend config should include KMS key ID"
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
