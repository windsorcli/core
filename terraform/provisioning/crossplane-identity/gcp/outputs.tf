output "service_account_emails" {
  description = "Map of resource type to the Google Service Account's email, for the Kubernetes ServiceAccount's iam.gke.io/gcp-service-account annotation."
  value       = { for k, sa in google_service_account.this : k => sa.email }
}
