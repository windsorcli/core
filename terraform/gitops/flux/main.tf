#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # Requeue dependency interval scales inversely with concurrency
  # Higher concurrency = shorter interval, lower = longer to reduce pressure
  requeue_interval = var.concurrency <= 3 ? "15s" : (var.concurrency <= 5 ? "10s" : "5s")

  # Appended to every controller's args. Default (leader_election=true) is an
  # empty list so no leader-election patch is emitted.
  leader_election_args = var.leader_election ? [] : ["--enable-leader-election=false"]

  notification_enabled    = var.mode == "push"
  webhook_token_supplied  = var.webhook_token != null && var.webhook_token != ""
  effective_webhook_token = local.webhook_token_supplied ? var.webhook_token : try(random_password.webhook_token[0].result, "")

  # Controllers the FluxInstance deploys. source/kustomize/helm are always on;
  # notification tracks push mode; the image controllers are opt-in.
  flux_components = concat(
    ["source-controller", "kustomize-controller", "helm-controller"],
    local.notification_enabled ? ["notification-controller"] : [],
    var.image_reflection ? ["image-reflector-controller"] : [],
    var.image_automation ? ["image-automation-controller"] : [],
  )

  # Extra container args per controller, matched by Deployment name. The operator
  # ships the base manifests without these flags; we append them via patches.
  controller_args = {
    "source-controller" = concat([
      "--concurrent=${var.concurrency}",
      "--requeue-dependency=${local.requeue_interval}",
      "--helm-cache-max-size=200",
      "--helm-cache-ttl=60m",
      "--helm-cache-purge-interval=5m",
    ], local.leader_election_args)
    "kustomize-controller" = concat([
      "--concurrent=${var.concurrency}",
      "--requeue-dependency=${local.requeue_interval}",
    ], local.leader_election_args)
    "helm-controller" = concat([
      "--concurrent=${max(2, var.concurrency - 1)}",
      "--requeue-dependency=${local.requeue_interval}",
    ], local.leader_election_args)
    "notification-controller"     = local.leader_election_args
    "image-reflector-controller"  = local.leader_election_args
    "image-automation-controller" = local.leader_election_args
  }

  # JSON6902 patches appending the args above, plus the kustomize-controller
  # memory limit carried over from the previous Helm-chart install.
  flux_patches = concat(
    [
      for name, cargs in local.controller_args : {
        target = { kind = "Deployment", name = name }
        patch = yamlencode([
          for a in cargs : {
            op    = "add"
            path  = "/spec/template/spec/containers/0/args/-"
            value = a
          }
        ])
      } if length(cargs) > 0
    ],
    [
      {
        target = { kind = "Deployment", name = "kustomize-controller" }
        patch = yamlencode({
          apiVersion = "apps/v1"
          kind       = "Deployment"
          metadata   = { name = "kustomize-controller" }
          spec = {
            template = {
              spec = {
                containers = [{
                  name      = "manager"
                  resources = { limits = { memory = "512Mi" } }
                }]
              }
            }
          }
        })
      }
    ]
  )
}

#-----------------------------------------------------------------------------------------------------------------------
# Set up Flux
#-----------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "flux_system" {
  metadata {
    name = var.flux_namespace
    labels = {
      "app.kubernetes.io/managed-by"            = "windsor-cli"
      "app.kubernetes.io/instance"              = "flux-system"
      "app.kubernetes.io/part-of"               = "flux"
      "pod-security.kubernetes.io/warn"         = "restricted"
      "pod-security.kubernetes.io/warn-version" = "latest"
      "kubernetes.io/metadata.name"             = var.flux_namespace
      "kubernetes.io/metadata.namespace"        = var.flux_namespace
      "kustomize.toolkit.fluxcd.io/name"        = "flux-system"
      "kustomize.toolkit.fluxcd.io/namespace"   = var.flux_namespace
    }
  }
}

# The operator installs the Flux CRDs and controllers and owns the FluxInstance CRD.
resource "helm_release" "flux_operator" {
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  name             = "flux-operator"
  version          = var.flux_operator_version
  namespace        = kubernetes_namespace_v1.flux_system.metadata[0].name
  create_namespace = false
  wait             = true
}

# The FluxInstance declares which controllers to run and how to tune them. The
# sync block is intentionally omitted: the windsor CLI creates the root
# GitRepository and Kustomizations, so the operator manages controllers only.
resource "helm_release" "flux_instance" {
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-instance"
  name             = "flux"
  version          = var.flux_operator_version
  namespace        = kubernetes_namespace_v1.flux_system.metadata[0].name
  create_namespace = false
  wait             = true
  depends_on       = [helm_release.flux_operator]
  values = [yamlencode({
    instance = {
      distribution = {
        version  = var.flux_version
        registry = "ghcr.io/fluxcd"
      }
      components = local.flux_components
      cluster = {
        type = "kubernetes"
        # Same NetworkPolicies the flux2 chart already shipped (allow all
        # intra-namespace traffic + egress, :8080 scraping, notification
        # webhooks) plus the operator UI on :9080. Enforced only where the CNI
        # supports it; a no-op on flannel.
        networkPolicy = true
      }
      kustomize = {
        patches = local.flux_patches
      }
    }
  })]
}

#-----------------------------------------------------------------------------------------------------------------------
# Wait for Flux to be ready
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # renovate: datasource=docker depName=kubectl package=alpine/k8s
  ready_gate_image = "alpine/k8s:1.36.2@sha256:44ef4942e171939b9c665a4a84beb80e2dcdb9a24330d4651cfdfd2e9deecc47"
}

# The ServiceAccount the readiness gate Job runs as.
resource "kubernetes_service_account_v1" "flux_ready_gate" {
  metadata {
    name      = "flux-ready-gate"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }
}

# The Role grants the gate read access to the FluxInstance status.
resource "kubernetes_role_v1" "flux_ready_gate" {
  metadata {
    name      = "flux-ready-gate"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }
  rule {
    api_groups = ["fluxcd.controlplane.io"]
    resources  = ["fluxinstances"]
    verbs      = ["get", "list", "watch"]
  }
}

# The RoleBinding ties the gate ServiceAccount to its Role.
resource "kubernetes_role_binding_v1" "flux_ready_gate" {
  metadata {
    name      = "flux-ready-gate"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.flux_ready_gate.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.flux_ready_gate.metadata[0].name
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }
}

# The Job blocks the apply until the operator reports the FluxInstance Ready,
# which means the toolkit CRDs and controllers are installed. Without it the
# helm releases return as soon as the FluxInstance object is created, and the
# windsor CLI races the operator when it applies the blueprint GitRepository.
resource "kubernetes_job_v1" "flux_ready_gate" {
  metadata {
    name      = "flux-ready-gate"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }
  spec {
    # Single attempt: the kubectl wait below already provides the readiness
    # patience, so retries would only push total runtime past the create
    # timeout. The TTL cleans up the finished Job and lets a later apply re-run
    # the gate (e.g. on a flux_version bump).
    backoff_limit              = 0
    ttl_seconds_after_finished = 300
    template {
      metadata {
        labels = {
          app = "flux-ready-gate"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.flux_ready_gate.metadata[0].name
        restart_policy       = "Never"
        security_context {
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name  = "wait"
          image = local.ready_gate_image
          command = ["/bin/sh", "-c", <<-EOT
            set -e
            i=1
            while [ $i -le 30 ]; do
              if kubectl get fluxinstance flux -n ${var.flux_namespace} >/dev/null 2>&1; then
                break
              fi
              echo "Waiting for FluxInstance/flux to exist (attempt $i/30)..."
              sleep 5
              i=$((i + 1))
            done
            echo "Waiting for FluxInstance/flux to report Ready..."
            kubectl wait --for=condition=Ready --timeout=10m fluxinstance/flux -n ${var.flux_namespace}
            echo "Flux is ready; toolkit CRDs and controllers are installed."
          EOT
          ]
          env {
            name  = "HOME"
            value = "/tmp"
          }
          security_context {
            run_as_non_root            = true
            run_as_user                = 65532
            allow_privilege_escalation = false
            read_only_root_filesystem  = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }
  wait_for_completion = true
  timeouts {
    create = "15m"
  }
  depends_on = [
    helm_release.flux_instance,
    kubernetes_role_binding_v1.flux_ready_gate,
  ]
}

#-----------------------------------------------------------------------------------------------------------------------
# Set up git authentication
#-----------------------------------------------------------------------------------------------------------------------

locals {
  known_hosts = {
    github = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
  }
  known_hosts_content = "${var.ssh_known_hosts}\n${local.known_hosts.github}"

  git_auth_data = var.ssh_public_key != "" ? {
    "identity"     = var.ssh_private_key
    "identity.pub" = var.ssh_public_key
    "known_hosts"  = local.known_hosts_content
    } : {
    username      = var.git_username
    password      = var.git_password
    "known_hosts" = local.known_hosts_content
  }
}

# The Secret holds the git credentials Flux uses to clone the repo. data_wo is
# write-only: the values are sent to the API but never persisted to state, so
# the credentials stay out of the state file. data_wo_revision is a hash of the
# content that bumps to push updates.
resource "kubernetes_secret_v1" "git_auth" {
  metadata {
    name      = var.git_auth_secret
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }

  data_wo          = local.git_auth_data
  data_wo_revision = parseint(substr(sha256(jsonencode(local.git_auth_data)), 0, 8), 16)
}

#-----------------------------------------------------------------------------------------------------------------------
# Set up webhook token
#-----------------------------------------------------------------------------------------------------------------------

resource "random_password" "webhook_token" {
  count   = local.notification_enabled && !local.webhook_token_supplied ? 1 : 0
  length  = 48
  special = false
}

resource "kubernetes_secret_v1" "webhook_token" {
  count = local.notification_enabled ? 1 : 0

  metadata {
    name      = "webhook-token"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }

  data_wo          = { token = local.effective_webhook_token }
  data_wo_revision = parseint(substr(sha256(local.effective_webhook_token), 0, 8), 16)
}

#-----------------------------------------------------------------------------------------------------------------------
# State migration blocks
#-----------------------------------------------------------------------------------------------------------------------

moved {
  from = kubernetes_namespace.flux_system
  to   = kubernetes_namespace_v1.flux_system
}

moved {
  from = kubernetes_secret.git_auth
  to   = kubernetes_secret_v1.git_auth
}

moved {
  from = kubernetes_secret.webhook_token
  to   = kubernetes_secret_v1.webhook_token
}

moved {
  from = kubernetes_secret_v1.webhook_token
  to   = kubernetes_secret_v1.webhook_token[0]
}

# Drop the old fluxcd-community flux2 Helm release from state WITHOUT uninstalling
# it. That chart renders the Flux CRDs as templates, so a real `helm uninstall`
# would delete them and cascade-delete every GitRepository/Kustomization/
# HelmRelease in the cluster. The operator adopts the live controllers in the
# same apply. No-op on clusters that never ran the flux2 chart.
removed {
  from = helm_release.flux_system
  lifecycle {
    destroy = false
  }
}
