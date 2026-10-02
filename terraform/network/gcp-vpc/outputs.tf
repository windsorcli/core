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

output "available_zones" {
  description = "Zones downstream node placement chooses from, capped to var.zone_count"
  value       = local.zone_names
}

output "private_zone_id" {
  description = "ID of the VPC-linked private DNS zone created from var.domain_name. Null when no domain_name was supplied."
  value       = try(google_dns_managed_zone.private[0].id, null)
}

output "private_zone_name" {
  description = "Name of the VPC-linked private DNS zone. Null when no domain_name was supplied."
  value       = try(google_dns_managed_zone.private[0].name, null)
}
