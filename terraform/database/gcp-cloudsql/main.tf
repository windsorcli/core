#---------------------------------------------------------------------------------------------------
# Providers Configuration
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.8.0"
    }
    # google_project_service_identity has no GA counterpart yet; every other
    # resource in this module stays on the google provider.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "8.7.0"
    }
  }
}

locals {
  # Longest context_id each name allows, after removing the characters its rule rejects.
  context_id_rules = {
    cloudsql = { id = var.context_id, max = 63 - length("cloudsql-") }
  }
  # Each rule's id, truncated and suffixed with a hash of the full id when longer than max.
  context_id_fit = {
    for k, r in local.context_id_rules : k => length(r.id) <= r.max ? r.id : "${substr(r.id, 0, max(r.max - 6, 0))}${substr(sha256(var.context_id), 0, 6)}"
  }

  # Non-null placeholder used only when operation is destroy and the sibling value is unavailable.
  network_id = var.operation == "destroy" ? coalesce(var.network_id, "projects/destroy-placeholder/global/networks/destroy-placeholder") : var.network_id
}

#---------------------------------------------------------------------------------------------------
# Private Service Connection
# GCP's equivalent of RDS's DB subnet group and Flexible Server's
# delegated subnet.
#---------------------------------------------------------------------------------------------------

resource "google_compute_global_address" "private_service_connection" {
  name          = "cloudsql-${local.context_id_fit.cloudsql}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = var.private_service_address
  prefix_length = 16
  network       = local.network_id
}

resource "google_service_networking_connection" "cloudsql" {
  network                 = local.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_connection.name]
  # Removes the peering directly: a normal delete can be refused with the
  # Cloud SQL instance still listed as a producer.
  deletion_policy = "REMOVE_PEERING"
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
  count    = var.manage_encryption_key && var.key_id == "" ? 1 : 0
  name     = "cloudsql-${local.context_id_fit.cloudsql}"
  location = var.region
}

resource "google_kms_crypto_key" "cloudsql" {
  # checkov:skip=CKV_GCP_82: Only created when key_id is unset; durable
  # deployments supply an externally-managed key instead of this one.
  count           = var.manage_encryption_key && var.key_id == "" ? 1 : 0
  name            = "cloudsql-${local.context_id_fit.cloudsql}"
  key_ring        = google_kms_key_ring.cloudsql[0].id
  rotation_period = "7776000s" # 90 days
}

# Cloud SQL's own service agent needs encrypt/decrypt on the key before it
# can use it for disk encryption.
resource "google_kms_crypto_key_iam_member" "cloudsql" {
  count         = var.manage_encryption_key && var.key_id == "" ? 1 : 0
  crypto_key_id = google_kms_crypto_key.cloudsql[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.cloudsql.email}"
}

