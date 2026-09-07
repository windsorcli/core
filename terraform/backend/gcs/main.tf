#---------------------------------------------------------------------------------------------------
# Providers Configuration
# This section defines the required providers for the Terraform configuration.
# Project and credentials come from GOOGLE_CLOUD_PROJECT / Application Default
# Credentials, matching how the azurerm backend relies on ARM_* env vars.
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.1.0"
    }
  }
}

#---------------------------------------------------------------------------------------------------
# GCS Bucket Creation
# This section creates the GCS bucket used for storing Terraform state.
# It ensures that the bucket is unique per project and enforces uniform access control.
#---------------------------------------------------------------------------------------------------

resource "google_storage_bucket" "this" {
  name                        = var.bucket_name != "" ? var.bucket_name : local.default_bucket_name
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  # Caps version accumulation so destroy-time empty doesn't have to
  # paginate through years of unexpired state writes.
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }

  dynamic "encryption" {
    for_each = var.enable_cmek ? [1] : []
    content {
      default_kms_key_name = google_kms_crypto_key.this[0].id
    }
  }

  dynamic "logging" {
    for_each = var.log_bucket_name != "" ? [1] : []
    content {
      log_bucket = var.log_bucket_name
    }
  }

  labels = local.labels

  depends_on = [google_kms_crypto_key_iam_member.gcs]
}

#---------------------------------------------------------------------------------------------------
# Bucket IAM
# Grants least-privilege object access to the specific principals that run
# Terraform, instead of relying on broad project-level IAM roles.
#---------------------------------------------------------------------------------------------------

resource "google_storage_bucket_iam_member" "terraform_state" {
  for_each = toset(var.terraform_state_principals)
  bucket   = google_storage_bucket.this.name
  role     = "roles/storage.objectUser"
  member   = each.value
}

#---------------------------------------------------------------------------------------------------
# Customer-Managed Encryption Key (CMEK)
# Optional. Google-managed encryption (the default) covers most cases;
# this is for operators with a compliance requirement to hold their own key.
#---------------------------------------------------------------------------------------------------

resource "google_kms_key_ring" "this" {
  count    = var.enable_cmek ? 1 : 0
  name     = "terraform-state-${var.context_id}"
  location = var.location
}

resource "google_kms_crypto_key" "this" {
  count           = var.enable_cmek ? 1 : 0
  name            = "terraform-state-${var.context_id}"
  key_ring        = google_kms_key_ring.this[0].id
  rotation_period = "7776000s" # 90 days
}

data "google_storage_project_service_account" "this" {
  count = var.enable_cmek ? 1 : 0
}

# GCS's own service agent needs encrypt/decrypt on the key before the
# bucket can use it as its default encryption key.
resource "google_kms_crypto_key_iam_member" "gcs" {
  count         = var.enable_cmek ? 1 : 0
  crypto_key_id = google_kms_crypto_key.this[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.this[0].email_address}"
}

#---------------------------------------------------------------------------------------------------
# Local Variables
# This section defines local variables for naming conventions and configuration.
#---------------------------------------------------------------------------------------------------

locals {
  default_bucket_name = var.bucket_name != "" ? var.bucket_name : "terraform-state-${var.context_id}"
  labels = merge(var.labels, {
    windsor_context_id = var.context_id
  })
}

#---------------------------------------------------------------------------------------------------
# Backend Configuration File
# This section generates the backend configuration file for Terraform.
#---------------------------------------------------------------------------------------------------

resource "local_file" "backend_config" {
  count = trim(var.context_path, " ") != "" ? 1 : 0
  content = templatefile("${path.module}/templates/backend.tftpl", {
    bucket = google_storage_bucket.this.name
    prefix = var.prefix
  })
  filename = "${var.context_path}/backend.tfvars"
}
