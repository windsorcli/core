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
      version = "3.1.2"
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
# Set up git authentication
#-----------------------------------------------------------------------------------------------------------------------

locals {
  known_hosts = {
    github = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
  }
  known_hosts_content = "${var.ssh_known_hosts}\n${local.known_hosts.github}"
}

resource "kubernetes_secret_v1" "git_auth" {
  metadata {
    name      = var.git_auth_secret
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }

  data = var.ssh_public_key != "" ? {
    "identity"     = var.ssh_private_key
    "identity.pub" = var.ssh_public_key
    "known_hosts"  = local.known_hosts_content
    } : {
    username      = var.git_username
    password      = var.git_password
    "known_hosts" = local.known_hosts_content
  }
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

  data = {
    token = local.effective_webhook_token
  }
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
