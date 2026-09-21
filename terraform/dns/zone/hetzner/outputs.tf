output "zone_id" {
  description = "Id of the created Hetzner DNS zone."
  value       = hcloud_zone.this.id
}

output "zone_name" {
  description = "Name of the created zone."
  value       = hcloud_zone.this.name
}

output "name_servers" {
  description = "Authoritative name servers for the zone. Configure these as NS records at your domain registrar so public DNS queries resolve through this zone (automated when parent_zone_name is set)."
  value       = hcloud_zone.this.authoritative_nameservers.assigned
}
