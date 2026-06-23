mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}

# Verifies that the module creates the Flux namespace, operator/instance Helm
# releases, and secrets with minimal configuration.
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
    condition     = helm_release.flux_operator.chart == "flux-operator"
    error_message = "Operator release should install the flux-operator chart"
  }

  assert {
    condition     = helm_release.flux_instance.chart == "flux-instance"
    error_message = "Instance release should install the flux-instance chart"
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

  assert {
    condition     = yamldecode(helm_release.flux_instance.values[0]).instance.cluster.networkPolicy == true
    error_message = "networkPolicy should be enabled to match the prior flux2 chart posture"
  }
}

# Tests a full configuration with all optional variables explicitly set.
run "full_configuration" {
  command = plan

  variables {
    flux_namespace        = "custom-gitops"
    flux_operator_version = "0.51.0"
    flux_version          = "2.6.0"
    ssh_private_key       = "PRIVATEKEY" # checkov:skip=CKV_SECRET_6: Test file, secrets are not real
    ssh_public_key        = "PUBLICKEY"
    ssh_known_hosts       = "KNOWNHOSTS"
    git_auth_secret       = "custom-auth" # checkov:skip=CKV_SECRET_6: Test file, secrets are not real
    git_username          = "customuser"
    git_password          = "custompass"
    webhook_token         = "webhooktoken123" # checkov:skip=CKV_SECRET_6: Test file, secrets are not real
  }

  assert {
    condition     = kubernetes_namespace_v1.flux_system.metadata[0].name == "custom-gitops"
    error_message = "Flux namespace should match input"
  }

  assert {
    condition     = helm_release.flux_operator.version == var.flux_operator_version
    error_message = "Operator chart version should match input variable"
  }

  assert {
    condition     = helm_release.flux_instance.version == var.flux_operator_version
    error_message = "Instance chart version should match input variable"
  }

  assert {
    condition     = yamldecode(helm_release.flux_instance.values[0]).instance.distribution.version == var.flux_version
    error_message = "FluxInstance distribution version should match flux_version"
  }

  assert {
    condition     = kubernetes_secret_v1.git_auth.metadata[0].name == "custom-auth"
    error_message = "Git auth secret name should match input"
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
    condition     = kubernetes_secret_v1.git_auth.data_wo_revision != null
    error_message = "Git auth secret should have a write-only data revision (even if empty)"
  }

  assert {
    condition     = kubernetes_secret_v1.webhook_token[0].data_wo_revision != null
    error_message = "Webhook token secret should have a write-only data revision (even if empty)"
  }
}

# Verifies pull mode drops notification-controller from the components and omits
# the webhook-token secret.
run "pull_mode_omits_notification_controller_and_secret" {
  command = plan

  variables {
    mode = "pull"
  }

  assert {
    condition     = !contains(yamldecode(helm_release.flux_instance.values[0]).instance.components, "notification-controller")
    error_message = "notification-controller should be omitted in pull mode"
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

# Verifies push mode (default) includes notification-controller and the secret.
run "push_mode_enables_notification_controller_and_secret" {
  command = plan

  assert {
    condition     = contains(yamldecode(helm_release.flux_instance.values[0]).instance.components, "notification-controller")
    error_message = "notification-controller should be present in push mode (default)"
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

# Verifies concurrency lands in the controller arg patches: source/kustomize get
# --concurrent=N, helm gets --concurrent=max(2, N-1).
run "concurrency_patches_controllers" {
  command = plan

  variables {
    concurrency = 6
  }

  assert {
    condition = length([
      for p in yamldecode(helm_release.flux_instance.values[0]).instance.kustomize.patches :
      p if p.target.name == "source-controller" && strcontains(p.patch, "--concurrent=6")
    ]) > 0
    error_message = "source-controller should receive --concurrent=6"
  }

  assert {
    condition = length([
      for p in yamldecode(helm_release.flux_instance.values[0]).instance.kustomize.patches :
      p if p.target.name == "helm-controller" && strcontains(p.patch, "--concurrent=5")
    ]) > 0
    error_message = "helm-controller should receive --concurrent=5 (max(2, 6-1))"
  }
}

# Verifies leader_election=false appends --enable-leader-election=false to every
# controller via a patch. Default (true) is covered by the clean run below.
run "leader_election_disabled" {
  command = plan

  variables {
    leader_election  = false
    image_automation = true
    image_reflection = true
  }

  assert {
    condition = alltrue([
      for name in ["source-controller", "kustomize-controller", "helm-controller", "notification-controller", "image-automation-controller", "image-reflector-controller"] :
      length([
        for p in yamldecode(helm_release.flux_instance.values[0]).instance.kustomize.patches :
        p if p.target.name == name && strcontains(p.patch, "--enable-leader-election=false")
      ]) > 0
    ])
    error_message = "every controller should receive --enable-leader-election=false"
  }
}

# Verifies the default (leader_election=true) emits no leader-election flag and
# no patch for controllers that only carry that flag (notification by default).
run "leader_election_default_leaves_flags_clean" {
  command = plan

  assert {
    condition = length([
      for p in yamldecode(helm_release.flux_instance.values[0]).instance.kustomize.patches :
      p if strcontains(p.patch, "--enable-leader-election=false")
    ]) == 0
    error_message = "no controller should receive the leader-election flag by default"
  }

  assert {
    condition = length([
      for p in yamldecode(helm_release.flux_instance.values[0]).instance.kustomize.patches :
      p if p.target.name == "notification-controller"
    ]) == 0
    error_message = "notification-controller should have no patch by default"
  }
}

# Verifies image-automation and image-reflector controllers are absent by default.
run "image_controllers_disabled_by_default" {
  command = plan

  assert {
    condition     = !contains(yamldecode(helm_release.flux_instance.values[0]).instance.components, "image-automation-controller")
    error_message = "image-automation-controller should be absent by default"
  }

  assert {
    condition     = !contains(yamldecode(helm_release.flux_instance.values[0]).instance.components, "image-reflector-controller")
    error_message = "image-reflector-controller should be absent by default"
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
    condition     = contains(yamldecode(helm_release.flux_instance.values[0]).instance.components, "image-automation-controller")
    error_message = "image-automation-controller should be present when image_automation=true"
  }

  assert {
    condition     = contains(yamldecode(helm_release.flux_instance.values[0]).instance.components, "image-reflector-controller")
    error_message = "image-reflector-controller should be present when image_reflection=true"
  }
}

# Verifies the readiness gate waits on the FluxInstance Ready condition in the
# Flux namespace, with a Role scoped to fluxinstances.
run "readiness_gate_waits_on_fluxinstance" {
  command = plan

  assert {
    condition     = kubernetes_job_v1.flux_ready_gate.metadata[0].namespace == "system-gitops"
    error_message = "readiness gate Job should run in the Flux namespace"
  }

  assert {
    condition     = strcontains(kubernetes_job_v1.flux_ready_gate.spec[0].template[0].spec[0].container[0].command[2], "kubectl wait --for=condition=Ready --timeout=10m fluxinstance/flux")
    error_message = "readiness gate should wait on the FluxInstance Ready condition"
  }

  assert {
    condition     = contains(kubernetes_role_v1.flux_ready_gate.rule[0].resources, "fluxinstances")
    error_message = "readiness gate Role should grant access to fluxinstances"
  }
}

# Verifies version input validation rules are enforced for both version inputs.
run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
    var.flux_operator_version,
    var.flux_version,
  ]
  variables {
    flux_operator_version = "0.52" # Missing patch version
    flux_version          = "2.5"  # Missing patch version
  }
}
