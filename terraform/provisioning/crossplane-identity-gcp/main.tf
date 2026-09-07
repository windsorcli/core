#---------------------------------------------------------------------------------------------------
# Provider Configuration
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
# Resource Catalog
#---------------------------------------------------------------------------------------------------

# Per-resource-type ServiceAccount, namespace, and IAM role. Same catalog
# shape as crossplane-identity-azure.
locals {
  catalog = {
    postgres = {
      namespace       = "system-provisioning"
      service_account = "provider-gcp-sql"
      role            = "roles/cloudsql.admin"
    }
  }

  selected = { for r in var.resources : r => local.catalog[r] }
}

#---------------------------------------------------------------------------------------------------
# Identities
#---------------------------------------------------------------------------------------------------

# The identity each selected resource type's Crossplane provider pod
# authenticates as via Workload Identity.
resource "google_service_account" "this" {
  for_each     = local.selected
  account_id   = "${var.cluster_name}-cp-${each.key}"
  display_name = "Crossplane provider-gcp-${each.key} for ${var.cluster_name}"
  project      = var.project_id
}

# Binds the Kubernetes ServiceAccount to this Google Service Account —
# GKE's own Workload Identity mechanism, the equivalent of Azure's
# federated credential and AWS's Pod Identity association.
resource "google_service_account_iam_member" "workload_identity" {
  for_each           = local.selected
  service_account_id = google_service_account.this[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.service_account}]"
}

#---------------------------------------------------------------------------------------------------
# IAM
#---------------------------------------------------------------------------------------------------

resource "google_project_iam_member" "this" {
  for_each = local.selected
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.this[each.key].email}"
}
