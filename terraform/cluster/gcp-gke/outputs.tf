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
