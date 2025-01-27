#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.7.3"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.35.1"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Set up Flux
#-----------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "flux_system" {
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
  namespace        = kubernetes_namespace.flux_system.metadata[0].name
  create_namespace = false
  wait             = true
  values = [yamlencode({
    kustomizeController = {
      container = {
        additionalArgs = [
          "--concurrent=10",
          "--requeue-dependency=5s"
        ]
        resources = {
          limits = {
            memory = "512Mi"
          }
        }
      }
    }
    helmController = {
      container = {
        additionalArgs = [
          "--concurrent=10",
          "--requeue-dependency=5s"
        ]
      }
    }
    sourceController = {
      container = {
        additionalArgs = [
          "--concurrent=10",
          "--requeue-dependency=5s",
          "--helm-cache-max-size=10",
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

resource "kubernetes_secret" "git_auth" {
  metadata {
    name      = var.git_auth_secret
    namespace = kubernetes_namespace.flux_system.metadata[0].name
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

resource "kubernetes_secret" "webhook_token" {
  metadata {
    name      = "webhook-token"
    namespace = kubernetes_namespace.flux_system.metadata[0].name
  }

  data = {
    token = var.webhook_token
  }
}
