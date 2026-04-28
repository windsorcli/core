#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the AKS cluster. Consumed by kustomize substitutions (txt-owner-id, etc.)."
  value       = azurerm_kubernetes_cluster.main.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the AKS cluster."
  value       = azurerm_resource_group.aks.name
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster. Used to bind external Workload Identity Federation credentials to the cluster."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "tenant_id" {
  description = "Azure AD tenant the cluster lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider) when authenticating via Workload Identity."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Subscription the cluster lives in. Required by cert-manager (azureDNS solver) and external-dns (Azure provider) when authenticating via Workload Identity."
  value       = data.azurerm_subscription.current.subscription_id
}

# cert-manager Workload Identity outputs — null when create_cert_manager_identity is false.

output "cert_manager_client_id" {
  description = "Client ID of the cert-manager User-Assigned Managed Identity. Annotate the cert-manager ServiceAccount with azure.workload.identity/client-id=<this> so token exchange targets the right identity. Null when the identity isn't provisioned."
  value       = try(azurerm_user_assigned_identity.cert_manager[0].client_id, null)
}

output "cert_manager_principal_id" {
  description = "Principal (object) ID of the cert-manager UAMI — useful for ad-hoc role grants outside this module."
  value       = try(azurerm_user_assigned_identity.cert_manager[0].principal_id, null)
}

# external-dns Workload Identity outputs — null when create_external_dns_identity is false.

output "external_dns_client_id" {
  description = "Client ID of the external-dns User-Assigned Managed Identity. Annotate the external-dns ServiceAccount with azure.workload.identity/client-id=<this> so token exchange targets the right identity. Null when the identity isn't provisioned."
  value       = try(azurerm_user_assigned_identity.external_dns[0].client_id, null)
}

output "external_dns_principal_id" {
  description = "Principal (object) ID of the external-dns UAMI — useful for ad-hoc role grants outside this module."
  value       = try(azurerm_user_assigned_identity.external_dns[0].principal_id, null)
}
