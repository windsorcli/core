output "zone_id" {
  description = "Id of the created Hetzner DNS zone."
  value       = hcloud_zone.this.id
}

output "zone_name" {
  description = "Name of the created zone."
  value       = hcloud_zone.this.name
}

output "nameservers" {
  description = "Authoritative Hetzner nameservers assigned to the zone. Delegate these at the parent (automated when parent_zone_name is set)."
  value       = hcloud_zone.this.authoritative_nameservers.assigned
}
