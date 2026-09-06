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

data "google_project" "this" {
  project_id = var.project_id
}

#---------------------------------------------------------------------------------------------------
# Private Service Connection
# Cloud SQL's private-IP mode peers through Service Networking, which needs
# a reserved address range and a VPC peering connection — the GCP
# equivalent of RDS's DB subnet group and Flexible Server's delegated
# subnet and private DNS zone.
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
# Same BYOK precedence as database/aws-rds and database/azure-postgres: an
# explicit key wins. Otherwise a dedicated key, unless the context is
# ephemeral — an ephemeral context uses Cloud SQL's platform-managed
# encryption instead.
#---------------------------------------------------------------------------------------------------

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

  lifecycle {
    prevent_destroy = true
  }
}

# Cloud SQL's own service agent needs encrypt/decrypt on the key before it
# can use it for disk encryption.
resource "google_kms_crypto_key_iam_member" "cloudsql" {
  count         = var.manage_encryption_key && var.kms_key_name == "" ? 1 : 0
  crypto_key_id = google_kms_crypto_key.cloudsql[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-cloud-sql.iam.gserviceaccount.com"
}

#---------------------------------------------------------------------------------------------------
# Admin Credentials
# Cloud SQL's User resource (unlike RDS's Instance or Flexible Server's own
# resource) has no auto-generate-and-write-to-secret mechanism for Postgres —
# passwordSecretRef only ever reads an existing Secret. This module
# generates the password and writes the Secret itself, one per named
# instance in var.admin_credentials, so the rest of the app-role/monitoring
# CronJob pattern (unchanged from RDS/Flexible Server) can read it the same
# way.
#---------------------------------------------------------------------------------------------------

resource "random_password" "admin" {
  for_each = var.admin_credentials
  length   = 24
  special  = false
}

resource "kubernetes_secret_v1" "admin_credentials" {
  for_each = var.admin_credentials
  metadata {
    name      = "${each.key}-admin-credentials"
    namespace = "system-provisioning"
  }
  data = {
    username = each.value.username
    password = random_password.admin[each.key].result
  }
}
