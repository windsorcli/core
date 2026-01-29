output "node" {
  value = var.node
}

output "endpoint" {
  value = var.endpoint
}

output "kubeconfig" {
  description = "The generated kubeconfig when bootstrap is true"
  value       = var.bootstrap ? talos_cluster_kubeconfig.this[0].kubeconfig_raw : null
  sensitive   = true
}
