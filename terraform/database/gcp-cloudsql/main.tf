#---------------------------------------------------------------------------------------------------
# Providers Configuration
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.1.0"
    }
    # google_project_service_identity has no GA counterpart yet; every other
    # resource in this module stays on the google provider.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "8.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

provider "google" {}
provider "google-beta" {}

#---------------------------------------------------------------------------------------------------
# Private Service Connection
# GCP's equivalent of RDS's DB subnet group and Flexible Server's
# delegated subnet.
#---------------------------------------------------------------------------------------------------

resource "google_compute_global_address" "private_service_connection" {
  name          = "cloudsql-${var.context_id}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
}

resource "google_service_networking_connection" "cloudsql" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_connection.name]
}

#---------------------------------------------------------------------------------------------------
# Customer-Managed Encryption Key (optional)
# BYOK precedence matches database/aws-rds and database/azure-postgres.
#---------------------------------------------------------------------------------------------------

# GCP provisions this service agent lazily. Force it up front for the
# IAM grant below.
resource "google_project_service_identity" "cloudsql" {
  provider = google-beta
  project  = var.project_id
  service  = "sqladmin.googleapis.com"
}

resource "google_kms_key_ring" "cloudsql" {
  count    = var.manage_encryption_key && var.kms_key_name == "" ? 1 : 0
  name     = "cloudsql-${var.context_id}"
  location = var.region
}

resource "google_kms_crypto_key" "cloudsql" {
  count           = var.manage_encryption_key && var.kms_key_name == "" ? 1 : 0
  name            = "cloudsql-${var.context_id}"
  key_ring        = google_kms_key_ring.cloudsql[0].id
  rotation_period = "7776000s" # 90 days
}

# Cloud SQL's own service agent needs encrypt/decrypt on the key before it
# can use it for disk encryption.
resource "google_kms_crypto_key_iam_member" "cloudsql" {
  count         = var.manage_encryption_key && var.kms_key_name == "" ? 1 : 0
  crypto_key_id = google_kms_crypto_key.cloudsql[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.cloudsql.email}"
}

#---------------------------------------------------------------------------------------------------
# Admin Credentials
# Cloud SQL's User resource has no auto-generate-and-write-to-secret
# mechanism. This module generates the password and writes the Secret
# itself, one per named instance in var.admin_credentials.
#
# Terraform runs before Flux, so this module creates its own copy of the
# system-provisioning namespace, matching cluster/aws-eks/additions's
# system-dns and gitops/flux's flux-system.
#---------------------------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "system_provisioning" {
  metadata {
    name = "system-provisioning"
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

resource "random_password" "admin" {
  for_each = var.admin_credentials
  length   = 24
  special  = false
}

resource "kubernetes_secret_v1" "admin_credentials" {
  for_each = var.admin_credentials
  metadata {
    name      = "${each.key}-admin-credentials"
    namespace = kubernetes_namespace_v1.system_provisioning.metadata[0].name
  }
  data = {
    username = each.value.username
    password = random_password.admin[each.key].result
  }
}
