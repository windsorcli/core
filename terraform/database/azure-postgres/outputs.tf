#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the dedicated resource group every Flexible Server in this context is created in."
  value       = azurerm_resource_group.postgres.name
}

output "resource_group_id" {
  description = "ID of the dedicated resource group, for scoping crossplane-identity-azure's role assignment."
  value       = azurerm_resource_group.postgres.id
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone Flexible Server's VNet-integrated mode resolves names against."
  value       = azurerm_private_dns_zone.postgres.id
}

# Precedence: an explicitly supplied key, then the dedicated key this module
# creates, then null (Flexible Server's platform-managed encryption).
output "key_vault_key_id" {
  description = "Versionless Key Vault key ID for Flexible Server storage encryption. Null when using platform-managed encryption."
  value = var.key_vault_key_id != "" ? var.key_vault_key_id : (
    length(azurerm_key_vault_key.postgres) > 0 ? azurerm_key_vault_key.postgres[0].versionless_id : null
  )
}

output "flexibleserver_cmk_identity_id" {
  description = "ID of the user-assigned identity Flexible Server's own identity block references to read the CMK. Null when using platform-managed encryption or a BYOK key (the operator's own identity already has access to that key)."
  value       = try(azurerm_user_assigned_identity.flexibleserver_cmk[0].id, null)
}
