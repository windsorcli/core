#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.7.3"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
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
}

#-----------------------------------------------------------------------------------------------------------------------
# Set up Flux
#-----------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "flux_system" {
  metadata {
    name = var.flux_namespace
    labels = {
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
    imageAutomationController = {
      image = "ghcr.io/fluxcd/image-automation-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/image-automation-controller package=ghcr.io/fluxcd/image-automation-controller
      tag = "v1.1.1@sha256:43617c9fbb4cf32aed7458647f62589575237ccb810f45bd7cb31f24126d4f22"
    }
    imageReflectionController = {
      image = "ghcr.io/fluxcd/image-reflector-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/image-reflector-controller package=ghcr.io/fluxcd/image-reflector-controller
      tag = "v1.1.1@sha256:4c12c4046dee6e32e11b7c6afeaf7910406b67ff0182d46eeedb128d367908cd"
    }
    kustomizeController = {
      image = "ghcr.io/fluxcd/kustomize-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/kustomize-controller package=ghcr.io/fluxcd/kustomize-controller
      tag = "v1.8.2@sha256:c480b89e26e42f6c112a4f683244a7979de3a2ca299bed7d5367ddf4fed706f0"
      container = {
        additionalArgs = [
          "--concurrent=${var.concurrency}",
          "--requeue-dependency=${local.requeue_interval}"
        ]
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
      tag = "v1.4.2@sha256:32dd3ec7a138245ff4cd755439099c544f4ce3a55f95aa69a97106c05a661def"
      container = {
        additionalArgs = [
          "--concurrent=${max(2, var.concurrency - 1)}",
          "--requeue-dependency=${local.requeue_interval}"
        ]
      }
    }
    notificationController = {
      image = "ghcr.io/fluxcd/notification-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/notification-controller package=ghcr.io/fluxcd/notification-controller
      tag = "v1.8.2@sha256:87806dc20caff40b37280ea3155cc9ef3e995402997c49a8f9f9c6bff57e1499"
    }
    sourceController = {
      image = "ghcr.io/fluxcd/source-controller"
      # renovate: datasource=docker depName=ghcr.io/fluxcd/source-controller package=ghcr.io/fluxcd/source-controller
      tag = "v1.8.1@sha256:7382d002cffeed2d877331353f95797e89c0aa7ecb432e661eeeda3e590b3293"
      container = {
        additionalArgs = [
          "--concurrent=${var.concurrency}",
          "--requeue-dependency=${local.requeue_interval}",
          "--helm-cache-max-size=200",
          "--helm-cache-ttl=60m",
          "--helm-cache-purge-interval=5m"
        ]
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

resource "kubernetes_secret_v1" "webhook_token" {
  metadata {
    name      = "webhook-token"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }

  data = {
    token = var.webhook_token
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
