output "storage_pool" {
  description = "Name of the shared storage pool."
  value       = incus_storage_pool.main.name
}
