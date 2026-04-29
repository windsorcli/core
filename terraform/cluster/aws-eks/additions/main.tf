# The AWS EKS Config module manages Kubernetes resources for AWS EKS clusters
# It provides configuration for system components like external-dns
# This module bridges Terraform and Kubernetes resources
# Key features: namespace management, configmap creation, auto-import of existing resources

terraform {
  required_version = ">=1.8"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.42.0"
    }
  }
}

locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "cluster-${var.context_id}"
}

data "aws_region" "current" {}

# =============================================================================
# Namespace Resources
# =============================================================================

# The system-dns namespace hosts DNS-related components
# It provides isolation and security context for DNS services
resource "kubernetes_namespace_v1" "system_dns" {
  metadata {
    name = "system-dns"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels
    ]
  }
}

# =============================================================================
# ConfigMap Resources
# =============================================================================

# The external-dns configmap provides configuration for the external-dns service
# It contains AWS-specific settings and credentials
resource "kubernetes_config_map_v1" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = kubernetes_namespace_v1.system_dns.metadata[0].name
  }

  data = {
    aws_region   = var.route53_region != null ? var.route53_region : data.aws_region.current.region
    txt_owner_id = local.cluster_name
  }
}

# =============================================================================
# State migration blocks
# =============================================================================

moved {
  from = kubernetes_namespace.system_dns
  to   = kubernetes_namespace_v1.system_dns
}

moved {
  from = kubernetes_config_map.external_dns
  to   = kubernetes_config_map_v1.external_dns
}
