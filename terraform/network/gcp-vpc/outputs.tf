#---------------------------------------------------------------------------------------------------
# Outputs
#---------------------------------------------------------------------------------------------------

output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.this.name
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = google_compute_subnetwork.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = google_compute_subnetwork.private.id
}

output "isolated_subnet_id" {
  description = "ID of the isolated subnet"
  value       = google_compute_subnetwork.isolated.id
}

output "region" {
  description = "GCP region the network and its subnets are created in"
  value       = var.region
}
