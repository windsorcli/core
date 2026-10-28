mock_provider "kubernetes" {}

# Verifies that the module creates the configured state namespace.
run "creates_namespace" {
  command = plan

  variables {
    namespace = "system-terraform"
  }

  assert {
    condition     = kubernetes_namespace_v1.this.metadata[0].name == "system-terraform"
    error_message = "Namespace should match the namespace input"
  }
}

# Verifies that invalid namespace names are rejected.
run "invalid_namespace" {
  command = plan

  expect_failures = [
    var.namespace,
  ]

  variables {
    namespace = "System_Terraform"
  }
}
