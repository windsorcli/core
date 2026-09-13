mock_provider "google" {}

# Verifies that the module creates resources with default naming conventions and basic configuration.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
    location   = "us-central1"
  }

  assert {
    condition     = google_storage_bucket.this.name == "terraform-state-test"
    error_message = "Bucket name should follow default naming convention"
  }

  assert {
    condition     = google_storage_bucket.this.location == "us-central1"
    error_message = "Bucket location should match the location variable"
  }

  assert {
    condition     = google_storage_bucket.this.uniform_bucket_level_access == true
    error_message = "Bucket should enforce uniform bucket-level access"
  }

  assert {
    condition     = google_storage_bucket.this.public_access_prevention == "enforced"
    error_message = "Bucket should enforce public access prevention regardless of IAM"
  }

  assert {
    condition     = google_storage_bucket.this.versioning[0].enabled == true
    error_message = "Bucket versioning should be enabled by default"
  }

  assert {
    condition     = google_storage_bucket.this.labels["windsor_context_id"] == "test"
    error_message = "Bucket should be labeled with windsor_context_id"
  }
}

# Regression: windsor_context_id must stay authoritative even if a caller passes
# a conflicting value through var.labels, since tag-based sweeping relies on it.
run "windsor_context_id_not_overridable" {
  command = plan

  variables {
    context_id = "test"
    labels = {
      windsor_context_id = "spoofed"
    }
  }

  assert {
    condition     = google_storage_bucket.this.labels["windsor_context_id"] == "test"
    error_message = "Bucket's windsor_context_id label must not be overridable via var.labels"
  }
}

# Tests a full configuration with all optional variables explicitly set.
run "full_configuration" {
  command = plan

  variables {
    context_id  = "test"
    location    = "us-east1"
    bucket_name = "custom-tfstate-bucket"
    prefix      = "custom/state"
  }

  assert {
    condition     = google_storage_bucket.this.name == "custom-tfstate-bucket"
    error_message = "Bucket name should match input"
  }

  assert {
    condition     = google_storage_bucket.this.location == "us-east1"
    error_message = "Bucket location should match input"
  }
}

# Validates that the backend configuration file is generated with correct
# values when a context path is provided.
run "backend_config_generation" {
  command = plan

  variables {
    context_id   = "test"
    context_path = "test"
  }

  assert {
    condition     = length(local_file.backend_config) == 1
    error_message = "Backend config should be generated with context path"
  }

  assert {
    condition = trimspace(local_file.backend_config[0].content) == trimspace(<<EOF
bucket = "terraform-state-test"
prefix = "terraform/state"
EOF
    )
    error_message = "Backend config should contain correct bucket and prefix"
  }
}

# Confirms that no backend configuration file is created when no context path
# is provided, preventing unnecessary file generation in the root directory.
run "backend_config_without_context_path" {
  command = plan

  variables {
    context_id   = "test-nopath"
    context_path = ""
  }

  assert {
    condition     = try(length(local_file.backend_config), 0) == 0
    error_message = "No backend config should be generated without context path"
  }
}

# No IAM bindings and no KMS resources by default — least-privilege grants
# and CMEK are both opt-in.
run "no_iam_or_cmek_by_default" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.terraform_state) == 0
    error_message = "No bucket IAM bindings should be created without terraform_state_principals"
  }

  assert {
    condition     = length(google_kms_crypto_key.this) == 0
    error_message = "No KMS key should be created without enable_cmek"
  }
}

# Grants the least-privilege object role to each configured principal.
run "terraform_state_principals_granted_object_access" {
  command = plan

  variables {
    context_id = "test"
    terraform_state_principals = [
      "user:operator@example.com",
      "serviceAccount:tf@test-project.iam.gserviceaccount.com",
    ]
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.terraform_state) == 2
    error_message = "Should create one IAM binding per configured principal"
  }

  assert {
    condition     = google_storage_bucket_iam_member.terraform_state["user:operator@example.com"].role == "roles/storage.objectUser"
    error_message = "Bucket IAM binding should grant the least-privilege object role"
  }
}

# CMEK: creates the key ring, key, and the IAM binding GCS needs before it
# can encrypt the bucket with that key.
run "cmek_enabled_creates_key_and_grants_gcs_access" {
  command = plan

  variables {
    context_id  = "test"
    enable_cmek = true
  }

  assert {
    condition     = google_kms_key_ring.this[0].name == "terraform-state-test"
    error_message = "KMS key ring should follow the default naming convention"
  }

  assert {
    condition     = google_kms_crypto_key.this[0].name == "terraform-state-test"
    error_message = "KMS crypto key should follow the default naming convention"
  }

  assert {
    condition     = google_kms_crypto_key_iam_member.gcs[0].role == "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    error_message = "GCS's service agent should be granted encrypt/decrypt on the key"
  }
}

# Verifies that an invalid bucket name is rejected.
run "invalid_bucket_name" {
  command = plan
  expect_failures = [
    var.bucket_name,
  ]
  variables {
    context_id  = "test"
    bucket_name = "UPPERCASE-not-allowed"
  }
}
