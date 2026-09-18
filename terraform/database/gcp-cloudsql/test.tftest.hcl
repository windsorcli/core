mock_provider "google" {}
mock_provider "google-beta" {}

# Verifies the private service connection and default CMK creation with no
# optional variables set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
    project_id = "test-project"
    network_id = "projects/test-project/global/networks/network-test"
  }

  assert {
    condition     = google_compute_global_address.private_service_connection.name == "cloudsql-test"
    error_message = "Reserved peering range should follow default naming convention"
  }

  assert {
    condition     = google_service_networking_connection.cloudsql.network == "projects/test-project/global/networks/network-test"
    error_message = "Service Networking connection should peer with the given network"
  }

  assert {
    condition     = length(google_kms_crypto_key.cloudsql) == 1
    error_message = "A dedicated KMS key should be created by default"
  }

  assert {
    condition     = length(google_kms_crypto_key_iam_member.cloudsql) == 1
    error_message = "Cloud SQL's service agent should be granted encrypt/decrypt on the key"
  }
}

# manage_encryption_key = false skips the dedicated key entirely (ephemeral
# contexts use Cloud SQL's platform-managed encryption).
run "manage_encryption_key_false_skips_kms" {
  command = plan

  variables {
    context_id            = "test"
    project_id            = "test-project"
    network_id            = "projects/test-project/global/networks/network-test"
    manage_encryption_key = false
  }

  assert {
    condition     = length(google_kms_crypto_key.cloudsql) == 0
    error_message = "No KMS key should be created when manage_encryption_key is false"
  }

  assert {
    condition     = length(google_kms_crypto_key_iam_member.cloudsql) == 0
    error_message = "No KMS IAM binding should be created when manage_encryption_key is false"
  }
}

# An explicit key_id wins over the dedicated key this module would
# otherwise create.
run "explicit_key_id_skips_dedicated_key" {
  command = plan

  variables {
    context_id = "test"
    project_id = "test-project"
    network_id = "projects/test-project/global/networks/network-test"
    key_id     = "projects/test-project/locations/us-central1/keyRings/existing/cryptoKeys/existing"
  }

  assert {
    condition     = length(google_kms_crypto_key.cloudsql) == 0
    error_message = "No dedicated KMS key should be created when key_id is explicitly set"
  }
}

# Verifies that a missing project_id is rejected.
run "missing_project_id" {
  command = plan
  expect_failures = [
    var.project_id,
  ]
  variables {
    context_id = "test"
    project_id = ""
    network_id = "projects/test-project/global/networks/network-test"
  }
}

# Verifies network_id is required during a normal apply.
run "network_id_required" {
  command = plan

  variables {
    context_id = "test"
    project_id = "test-project"
    network_id = null
  }

  expect_failures = [var.network_id]
}

# Verifies a destroy operation relaxes the network_id validation, so a plan
# can still be produced once network/gcp-vpc is gone.
run "destroy_operation_relaxes_sibling_input_validation" {
  command = plan

  variables {
    context_id = "test"
    project_id = "test-project"
    operation  = "destroy"
    network_id = null
  }
}
