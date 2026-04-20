#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.7.3"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
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

  # Appended to every controller's additionalArgs. Default (leader_election=true)
  # is an empty list so the rendered Helm values stay byte-identical to before.
  leader_election_args = var.leader_election ? [] : ["--enable-leader-election=false"]

  notification_enabled    = var.mode == "push"
  webhook_token_supplied  = var.webhook_token != null && var.webhook_token != ""
  effective_webhook_token = local.webhook_token_supplied ? var.webhook_token : try(random_password.webhook_token[0].result, "")
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

resource "helm_release" "flux_system" {
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  name             = "flux2"
  version          = var.flux_helm_version
  namespace        = kubernetes_namespace_v1.flux_system.metadata[0].name
  create_namespace = false
  wait             = true
  values = [yamlencode({
    imageAutomationController = merge({
      create = var.image_automation
      image  = "ghcr.io/fluxcd/image-automation-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/image-automation-controller package=ghcr.io/fluxcd/image-automation-controller
      tag = "v1.1.1@sha256:43617c9fbb4cf32aed7458647f62589575237ccb810f45bd7cb31f24126d4f22"
      }, var.leader_election ? {} : {
      container = { additionalArgs = local.leader_election_args }
    })
    imageReflectionController = merge({
      create = var.image_reflection
      image  = "ghcr.io/fluxcd/image-reflector-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/image-reflector-controller package=ghcr.io/fluxcd/image-reflector-controller
      tag = "v1.1.1@sha256:4c12c4046dee6e32e11b7c6afeaf7910406b67ff0182d46eeedb128d367908cd"
      }, var.leader_election ? {} : {
      container = { additionalArgs = local.leader_election_args }
    })
    kustomizeController = {
      image = "ghcr.io/fluxcd/kustomize-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/kustomize-controller package=ghcr.io/fluxcd/kustomize-controller
      tag = "v1.8.3@sha256:c59e81059330a55203bf60806229a052617134d8b557c1bd83cdc69a8ece7ea2"
      container = {
        additionalArgs = concat([
          "--concurrent=${var.concurrency}",
          "--requeue-dependency=${local.requeue_interval}"
        ], local.leader_election_args)
        resources = {
          limits = {
            memory = "512Mi"
          }
        }
      }
    }
    helmController = {
      image = "ghcr.io/fluxcd/helm-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/helm-controller package=ghcr.io/fluxcd/helm-controller
      tag = "v1.5.3@sha256:b150af0cd7a501dafe2374b1d22c39abf0572465df4fa1fb99b37927b0d95d75"
      container = {
        additionalArgs = concat([
          "--concurrent=${max(2, var.concurrency - 1)}",
          "--requeue-dependency=${local.requeue_interval}"
        ], local.leader_election_args)
      }
    }
    notificationController = merge({
      create = local.notification_enabled
      image  = "ghcr.io/fluxcd/notification-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/notification-controller package=ghcr.io/fluxcd/notification-controller
      tag = "v1.8.3@sha256:a9e22d4aeec507abb3abc0e6ad3aeb3b672fd03d5776c785399aedec263a603f"
      }, var.leader_election ? {} : {
      container = { additionalArgs = local.leader_election_args }
    })
    sourceController = {
      image = "ghcr.io/fluxcd/source-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/source-controller package=ghcr.io/fluxcd/source-controller
      tag = "v1.8.2@sha256:f2f6fd483b9a8b8c69f8ebe9f2277be23093a2b552b3578a6db15710d736bb0e"
      container = {
        additionalArgs = concat([
          "--concurrent=${var.concurrency}",
          "--requeue-dependency=${local.requeue_interval}",
          "--helm-cache-max-size=200",
          "--helm-cache-ttl=60m",
          "--helm-cache-purge-interval=5m"
        ], local.leader_election_args)
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
