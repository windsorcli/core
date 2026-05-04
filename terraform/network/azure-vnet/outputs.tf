#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "vnet_id" {
  description = "The ID of the VNet"
  value       = azurerm_virtual_network.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = azurerm_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = azurerm_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "List of isolated subnet IDs"
  value       = azurerm_subnet.isolated[*].id
}

output "private_zone_id" {
  description = "Resource ID of the VNet-linked private DNS zone created from var.domain_name. Null when no domain_name was supplied."
  value       = try(azurerm_private_dns_zone.main[0].id, null)
}

output "private_zone_name" {
  description = "Name of the VNet-linked private DNS zone. Null when no domain_name was supplied."
  value       = try(azurerm_private_dns_zone.main[0].name, null)
}

output "resource_group_name" {
  description = "Name of the resource group holding the VNet and (when set) the private DNS zone."
  value       = azurerm_resource_group.main.name
}

output "subscription_id" {
  description = "Subscription ID resolved from the VNet resource."
  value       = element(split("/", azurerm_virtual_network.main.id), 2)
}
