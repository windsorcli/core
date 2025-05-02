#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "public_subnet_ids" {
  description = "IDs of created public subnets"
  value       = azurerm_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of created private subnets" 
  value       = azurerm_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "IDs of created data subnets"
  value       = azurerm_subnet.data[*].id
}
