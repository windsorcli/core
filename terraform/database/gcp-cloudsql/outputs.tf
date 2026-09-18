#---------------------------------------------------------------------------------------------------
# Outputs
#---------------------------------------------------------------------------------------------------

# Precedence: an explicitly supplied key, then the dedicated key this module
# creates, then empty string (Cloud SQL's platform-managed encryption).
output "key_id" {
  description = "KMS CryptoKey resource name for Cloud SQL storage encryption. Empty when using platform-managed encryption."
  value = var.key_id != "" ? var.key_id : (
    length(google_kms_crypto_key.cloudsql) > 0 ? google_kms_crypto_key.cloudsql[0].id : ""
  )
}

output "private_vpc_connection" {
  description = "Service Networking connection Cloud SQL's private-IP mode peers through. A DatabaseInstance depends on this existing, not on any value it exposes."
  value       = google_service_networking_connection.cloudsql.id
}
