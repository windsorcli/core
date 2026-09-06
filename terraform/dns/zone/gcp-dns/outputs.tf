#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

# The managed zone's resource name, not its domain. cert-manager (cloudDNS
# solver) and external-dns (google provider) discover the zone by project +
# domain, but the IAM bindings that scope their Workload Identity Federation
# service accounts to just this zone need this name.
output "zone_name" {
  description = "The GCP resource name of the managed zone."
  value       = google_dns_managed_zone.main.name
}

output "domain_name" {
  description = "The fully-qualified domain name of the managed zone."
  value       = var.domain_name
}

output "name_servers" {
  description = "Authoritative name servers for the zone. Configure these as NS records at your domain registrar so public DNS queries resolve through this zone."
  value       = google_dns_managed_zone.main.name_servers
}

output "project_id" {
  description = "GCP project the zone lives in. Required by cert-manager (cloudDNS solver) and external-dns (google provider)."
  value       = var.project_id
}
