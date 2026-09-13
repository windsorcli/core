output "client_ids" {
  description = "Map of resource type to the identity's client ID, for the DeploymentRuntimeConfig ServiceAccount annotation."
  value       = { for k, i in azurerm_user_assigned_identity.this : k => i.client_id }
}

output "tenant_id" {
  description = "Azure AD tenant ID shared by every identity this module creates."
  value       = length(azurerm_user_assigned_identity.this) > 0 ? values(azurerm_user_assigned_identity.this)[0].tenant_id : null
}
