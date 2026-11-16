#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "zone_id" {
  description = "The zone ID. Consumed by external-dns as its zone filter."
  value       = var.create_zone ? cloudflare_zone.this[0].id : data.cloudflare_zone.this[0].id
}

output "domain_name" {
  description = "The name of the zone."
  value       = var.domain_name
}

output "name_servers" {
  description = "The authoritative name servers for the zone. Set these at the domain registrar to activate a created zone."
  value       = var.create_zone ? cloudflare_zone.this[0].name_servers : data.cloudflare_zone.this[0].name_servers
}

output "status" {
  description = "The zone status. A created zone is pending until the registrar delegates it."
  value       = var.create_zone ? cloudflare_zone.this[0].status : data.cloudflare_zone.this[0].status
}
