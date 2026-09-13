mock_provider "google" {}

# Verifies default behavior with no resource types selected — no
# identities, no bindings.
run "no_resources_creates_nothing" {
  command = plan

  variables {
    project_id   = "test-project"
    cluster_name = "cluster-test"
  }

  assert {
    condition     = length(google_service_account.this) == 0
    error_message = "No service accounts should be created with an empty resources set"
  }
}

# postgres selects exactly one identity, one Workload Identity binding, and
# one IAM role grant.
run "postgres_creates_identity_and_iam" {
  command = plan

  variables {
    project_id   = "test-project"
    cluster_name = "cluster-test"
    resources    = ["postgres"]
  }

  assert {
    condition     = google_service_account.this["postgres"].account_id == "cluster-test-cp-postgres"
    error_message = "Service account should follow the fixed naming convention"
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity["postgres"].role == "roles/iam.workloadIdentityUser"
    error_message = "Workload Identity binding should grant iam.workloadIdentityUser"
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity["postgres"].member == "serviceAccount:test-project.svc.id.goog[system-provisioning/provider-gcp-sql]"
    error_message = "Workload Identity binding should scope to the catalog's namespace/service account"
  }

  assert {
    condition     = google_project_iam_member.this["postgres"].role == "roles/cloudsql.admin"
    error_message = "IAM role grant should use the predefined Cloud SQL admin role"
  }
}

# Verifies that an invalid resource type is rejected at validate time.
run "invalid_resource_type_rejected" {
  command = plan
  expect_failures = [
    var.resources,
  ]
  variables {
    project_id   = "test-project"
    cluster_name = "cluster-test"
    resources    = ["not-a-real-resource"]
  }
}

# Verifies that a missing cluster_name is rejected.
run "missing_cluster_name" {
  command = plan
  expect_failures = [
    var.cluster_name,
  ]
  variables {
    project_id   = "test-project"
    cluster_name = ""
  }
}
