output "storage_pool" {
  description = "Name of the shared storage pool."
  value       = incus_storage_pool.main.name
}

output "network" {
  description = "Name of the shared physical network, or null when the module creates none."
  value       = one(incus_network.main[*].name)
}

output "projects" {
  description = "Names of the projects the module creates."
  value       = sort([for p in incus_project.main : p.name])
}
