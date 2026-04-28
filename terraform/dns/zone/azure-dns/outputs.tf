#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

# Full Azure resource ID of the zone. cert-manager DNS Zone Contributor
# role assignments scope to this — narrows the credential's reach to one
# zone instead of the whole subscription.
output "zone_id" {
  description = "The full Azure resource ID of the DNS zone."
  value       = azurerm_dns_zone.main.id
}

output "zone_name" {
  description = "The fully-qualified domain name of the DNS zone."
  value       = azurerm_dns_zone.main.name
}

output "name_servers" {
  description = "Authoritative name servers for the zone. Configure these as NS records at your domain registrar so public DNS queries resolve through this zone."
  value       = azurerm_dns_zone.main.name_servers
}

output "resource_group_name" {
  description = "The resource group the DNS zone lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider)."
  value       = data.azurerm_resource_group.dns.name
}

output "subscription_id" {
  description = "Subscription the zone lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider)."
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Tenant the zone lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider) when authenticating via Workload Identity."
  value       = data.azurerm_subscription.current.tenant_id
}
