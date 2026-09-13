#---------------------------------------------------------------------------------------------------
# Outputs
#---------------------------------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the GKE cluster. Consumed by kustomize substitutions (txt-owner-id, etc.)."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified ID of the GKE cluster."
  value       = google_container_cluster.this.id
}

output "endpoint" {
  description = "IP address of the cluster's control plane endpoint."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "workload_pool" {
  description = "Workload Identity pool (PROJECT_ID.svc.id.goog). Required to bind Workload Identity Federation credentials to Kubernetes ServiceAccounts."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "project_id" {
  description = "GCP project the cluster lives in."
  value       = var.project_id
}

output "region" {
  description = "GCP region the cluster lives in."
  value       = var.region
}

# cert-manager Workload Identity output — null when create_cert_manager_identity is false.
output "cert_manager_service_account_email" {
  description = "Email of the cert-manager Google Service Account. Annotate cert-manager's KSA with iam.gke.io/gcp-service-account to bind it."
  value       = try(google_service_account.cert_manager[0].email, null)
}

# external-dns Workload Identity output — null when create_external_dns_identity is false.
output "external_dns_service_account_email" {
  description = "Email of the external-dns Google Service Account. Annotate external-dns's KSA with iam.gke.io/gcp-service-account to bind it."
  value       = try(google_service_account.external_dns[0].email, null)
}
