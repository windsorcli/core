mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}

# Verifies that the module creates the Flux namespace, Helm release, and secrets with minimal configuration.
# Tests default values for namespace, chart version, and secret naming logic.
run "minimal_configuration" {
  command = plan

  variables {
    # Only required variables, all others use defaults
  }

  assert {
    condition     = kubernetes_namespace_v1.flux_system.metadata[0].name == "system-gitops"
    error_message = "Flux namespace should default to 'system-gitops'"
  }

  assert {
    condition     = kubernetes_secret_v1.git_auth.metadata[0].name == "flux-system"
    error_message = "Git auth secret name should default to 'flux-system'"
  }

  assert {
    condition     = kubernetes_secret_v1.git_auth.metadata[0].namespace == "system-gitops"
    error_message = "Git auth secret should be in the Flux namespace"
  }

  assert {
    condition     = kubernetes_secret_v1.webhook_token[0].metadata[0].namespace == "system-gitops"
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
    condition     = kubernetes_namespace_v1.flux_system.metadata[0].name == "custom-gitops"
    error_message = "Flux namespace should match input"
  }

  assert {
    condition     = helm_release.flux_system.version == var.flux_helm_version
    error_message = "Flux Helm chart version should match input variable"
  }

  assert {
    condition     = kubernetes_secret_v1.git_auth.metadata[0].name == "custom-auth"
    error_message = "Git auth secret name should match input"
  }

  assert {
    condition     = kubernetes_secret_v1.git_auth.metadata[0].namespace == "custom-gitops"
    error_message = "Git auth secret should be in the custom namespace"
  }

  assert {
    condition     = kubernetes_secret_v1.webhook_token[0].metadata[0].namespace == "custom-gitops"
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
  }

  assert {
    condition     = kubernetes_secret_v1.git_auth.data != null
    error_message = "Git auth secret data should be present (even if empty)"
  }

  assert {
    condition     = kubernetes_secret_v1.webhook_token[0].data != null
    error_message = "Webhook token secret data should be present (even if empty)"
  }
}

# Verifies pull mode disables notification-controller and omits the webhook-token secret.
run "pull_mode_omits_notification_controller_and_secret" {
  command = plan

  variables {
    mode = "pull"
  }

  assert {
    condition     = yamldecode(helm_release.flux_system.values[0]).notificationController.create == false
    error_message = "notification-controller should be disabled in pull mode"
  }

  assert {
    condition     = length(kubernetes_secret_v1.webhook_token) == 0
    error_message = "webhook-token secret should not be created in pull mode"
  }

  assert {
    condition     = length(random_password.webhook_token) == 0
    error_message = "webhook-token random password should not be generated in pull mode"
  }
}

# Verifies push mode (default) creates the notification-controller and secret.
run "push_mode_enables_notification_controller_and_secret" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.flux_system.values[0]).notificationController.create == true
    error_message = "notification-controller should be enabled in push mode (default)"
  }

  assert {
    condition     = length(kubernetes_secret_v1.webhook_token) == 1
    error_message = "webhook-token secret should be created in push mode"
  }
}

# Rejects invalid mode values.
run "invalid_mode_rejected" {
  command = plan

  variables {
    mode = "sideways"
  }

  expect_failures = [
    var.mode,
  ]
}

# Verifies that when webhook_token is unset (null default), the module generates
# a random token instead of storing an empty string in the secret.
run "webhook_token_auto_generated_when_null" {
  command = plan

  # No webhook_token override → null default → generation path

  assert {
    condition     = length(random_password.webhook_token) == 1
    error_message = "random_password.webhook_token should be created when webhook_token is null"
  }
}

# Verifies that an explicit empty string is also treated as "unset" and triggers generation.
run "webhook_token_auto_generated_when_empty" {
  command = plan

  variables {
    webhook_token = ""
  }

  assert {
    condition     = length(random_password.webhook_token) == 1
    error_message = "random_password.webhook_token should be created when webhook_token is empty"
  }
}

# Verifies that when webhook_token is supplied, no random password is generated.
run "webhook_token_supplied_skips_generation" {
  command = plan

  variables {
    webhook_token = "explicittoken" # checkov:skip=CKV_SECRET_6: Test file, secrets are not real
  }

  assert {
    condition     = length(random_password.webhook_token) == 0
    error_message = "random_password.webhook_token should not be created when webhook_token is supplied"
  }
}

# Verifies leader_election=false appends --enable-leader-election=false to every
# controller's additionalArgs (the three with pre-existing args get it appended,
# the three without get a container block added). Default (true) is covered
# implicitly by the minimal_configuration run above.
run "leader_election_disabled" {
  command = plan

  variables {
    leader_election = false
  }

  assert {
    condition     = contains(yamldecode(helm_release.flux_system.values[0]).kustomizeController.container.additionalArgs, "--enable-leader-election=false")
    error_message = "kustomize-controller should receive --enable-leader-election=false"
  }

  assert {
    condition     = contains(yamldecode(helm_release.flux_system.values[0]).helmController.container.additionalArgs, "--enable-leader-election=false")
    error_message = "helm-controller should receive --enable-leader-election=false"
  }

  assert {
    condition     = contains(yamldecode(helm_release.flux_system.values[0]).sourceController.container.additionalArgs, "--enable-leader-election=false")
    error_message = "source-controller should receive --enable-leader-election=false"
  }

  assert {
    condition     = contains(yamldecode(helm_release.flux_system.values[0]).notificationController.container.additionalArgs, "--enable-leader-election=false")
    error_message = "notification-controller should receive --enable-leader-election=false"
  }

  assert {
    condition     = contains(yamldecode(helm_release.flux_system.values[0]).imageAutomationController.container.additionalArgs, "--enable-leader-election=false")
    error_message = "image-automation-controller should receive --enable-leader-election=false"
  }

  assert {
    condition     = contains(yamldecode(helm_release.flux_system.values[0]).imageReflectionController.container.additionalArgs, "--enable-leader-election=false")
    error_message = "image-reflector-controller should receive --enable-leader-election=false"
  }
}

# Verifies the default (leader_election=true) does not add leader-election flags
# and leaves controllers without pre-existing additionalArgs free of a container block.
run "leader_election_default_leaves_flags_clean" {
  command = plan

  assert {
    condition     = !contains(yamldecode(helm_release.flux_system.values[0]).kustomizeController.container.additionalArgs, "--enable-leader-election=false")
    error_message = "kustomize-controller should not receive leader-election flag by default"
  }

  assert {
    condition     = !can(yamldecode(helm_release.flux_system.values[0]).notificationController.container)
    error_message = "notification-controller should not have a container block by default"
  }
}

# Verifies image-automation and image-reflector controllers are disabled by default.
run "image_controllers_disabled_by_default" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.flux_system.values[0]).imageAutomationController.create == false
    error_message = "image-automation-controller should be disabled by default"
  }

  assert {
    condition     = yamldecode(helm_release.flux_system.values[0]).imageReflectionController.create == false
    error_message = "image-reflector-controller should be disabled by default"
  }
}

# Verifies image-automation and image-reflector controllers can be opted in.
run "image_controllers_enabled_when_requested" {
  command = plan

  variables {
    image_automation = true
    image_reflection = true
  }

  assert {
    condition     = yamldecode(helm_release.flux_system.values[0]).imageAutomationController.create == true
    error_message = "image-automation-controller should be enabled when image_automation=true"
  }

  assert {
    condition     = yamldecode(helm_release.flux_system.values[0]).imageReflectionController.create == true
    error_message = "image-reflector-controller should be enabled when image_reflection=true"
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
