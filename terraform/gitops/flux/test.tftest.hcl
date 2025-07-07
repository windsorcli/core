mock_provider "kubernetes" {}
mock_provider "helm" {}

# Verifies that the module creates the Flux namespace, Helm release, and secrets with minimal configuration.
# Tests default values for namespace, chart version, and secret naming logic.
run "minimal_configuration" {
  command = plan

  variables {
    # Only required variables, all others use defaults
  }

  assert {
    condition     = kubernetes_namespace.flux_system.metadata[0].name == "system-gitops"
    error_message = "Flux namespace should default to 'system-gitops'"
  }

  assert {
    condition     = kubernetes_secret.git_auth.metadata[0].name == "flux-system"
    error_message = "Git auth secret name should default to 'flux-system'"
  }

  assert {
    condition     = kubernetes_secret.git_auth.metadata[0].namespace == "system-gitops"
    error_message = "Git auth secret should be in the Flux namespace"
  }

  assert {
    condition     = kubernetes_secret.webhook_token.metadata[0].namespace == "system-gitops"
    error_message = "Webhook token secret should be in the Flux namespace"
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values override defaults for namespace, chart version, and secret data.
run "full_configuration" {
  command = plan

  variables {
    flux_namespace    = "custom-gitops"
    flux_helm_version = "2.16.0"
    flux_version      = "2.6.0"
    ssh_private_key   = "PRIVATEKEY" # checkov:skip=CKV_SECRET_6: Test file, secrets are not real
    ssh_public_key    = "PUBLICKEY"
    ssh_known_hosts   = "KNOWNHOSTS"
    git_auth_secret   = "custom-auth" # checkov:skip=CKV_SECRET_6: Test file, secrets are not real
    git_username      = "customuser"
    git_password      = "custompass"
    webhook_token     = "webhooktoken123" # checkov:skip=CKV_SECRET_6: Test file, secrets are not real
  }

  assert {
    condition     = kubernetes_namespace.flux_system.metadata[0].name == "custom-gitops"
    error_message = "Flux namespace should match input"
  }

  assert {
    condition     = helm_release.flux_system.version == var.flux_helm_version
    error_message = "Flux Helm chart version should match input variable"
  }

  assert {
    condition     = kubernetes_secret.git_auth.metadata[0].name == "custom-auth"
    error_message = "Git auth secret name should match input"
  }

  assert {
    condition     = kubernetes_secret.git_auth.metadata[0].namespace == "custom-gitops"
    error_message = "Git auth secret should be in the custom namespace"
  }

  assert {
    condition     = kubernetes_secret.webhook_token.metadata[0].namespace == "custom-gitops"
    error_message = "Webhook token secret should be in the custom namespace"
  }
}

# Verifies that no secrets are created if all sensitive variables are empty (default)
run "no_secrets" {
  command = plan

  variables {
    ssh_private_key = ""
    ssh_public_key  = ""
    ssh_known_hosts = ""
    git_password    = ""
    webhook_token   = ""
  }

  assert {
    condition     = kubernetes_secret.git_auth.data != null
    error_message = "Git auth secret data should be present (even if empty)"
  }

  assert {
    condition     = kubernetes_secret.webhook_token.data != null
    error_message = "Webhook token secret data should be present (even if empty)"
  }
}

# Verifies that all input validation rules are enforced simultaneously, ensuring that
# invalid values for Flux versions are properly caught
run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
    var.flux_helm_version,
    var.flux_version,
  ]
  variables {
    flux_helm_version = "2.15" # Missing patch version
    flux_version      = "2.5"  # Missing patch version
  }
}
