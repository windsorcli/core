output "namespace" {
  description = "Namespace that holds the Terraform state Secrets."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}
