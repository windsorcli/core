#---------------------------------------------------------------------------------------------------
# Providers Configuration
# The provider reaches the state cluster through the backend's config_path and config_context,
# or through KUBE_CONFIG_PATH when neither is set.
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.3.0"
    }
  }
}

provider "kubernetes" {
  config_path    = var.config_path != "" ? var.config_path : null
  config_context = var.config_context != "" ? var.config_context : null
}

#---------------------------------------------------------------------------------------------------
# State Namespace
# This section creates the namespace that holds the Terraform state Secrets.
#---------------------------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}
