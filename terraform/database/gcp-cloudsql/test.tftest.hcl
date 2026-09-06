mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}
mock_provider "kubernetes" {}

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

  assert {
    condition     = length(kubernetes_secret_v1.admin_credentials) == 0
    error_message = "No admin credential Secrets should be created with an empty admin_credentials map"
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

# An explicit kms_key_name wins over the dedicated key this module would
# otherwise create.
run "explicit_kms_key_name_skips_dedicated_key" {
  command = plan

  variables {
    context_id   = "test"
    project_id   = "test-project"
    network_id   = "projects/test-project/global/networks/network-test"
    kms_key_name = "projects/test-project/locations/us-central1/keyRings/existing/cryptoKeys/existing"
  }

  assert {
    condition     = length(google_kms_crypto_key.cloudsql) == 0
    error_message = "No dedicated KMS key should be created when kms_key_name is explicitly set"
  }
}

# Each entry in admin_credentials generates its own password and Secret,
# named by the fixed <key>-admin-credentials convention.
run "admin_credentials_generates_secret_per_instance" {
  command = plan

  variables {
    context_id = "test"
    project_id = "test-project"
    network_id = "projects/test-project/global/networks/network-test"
    admin_credentials = {
      demo-db = {
        username = "demo"
      }
    }
  }

  assert {
    condition     = kubernetes_secret_v1.admin_credentials["demo-db"].metadata[0].name == "demo-db-admin-credentials"
    error_message = "Admin credential Secret should follow the fixed <instance>-admin-credentials naming convention"
  }

  assert {
    condition     = kubernetes_secret_v1.admin_credentials["demo-db"].metadata[0].namespace == "system-provisioning"
    error_message = "Admin credential Secret should land in system-provisioning"
  }

  assert {
    condition     = kubernetes_secret_v1.admin_credentials["demo-db"].data["username"] == "demo"
    error_message = "Admin credential Secret should carry the configured username"
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
