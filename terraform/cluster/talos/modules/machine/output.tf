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

output "instance_id" {
  description = "Identity of the underlying compute instance, as passed in."
  value       = var.instance_id
}

output "health_check_id" {
  description = "ID of the node health check, known once the node is configured and healthy."
  value       = null_resource.node_healthcheck.id
}
