#---------------------------------------------------------------------------------------------------
# Outputs
#---------------------------------------------------------------------------------------------------

# Precedence: an explicitly supplied key, then the dedicated key this module
# creates, then empty string (Cloud SQL's platform-managed encryption).
output "kms_key_name" {
  description = "KMS CryptoKey resource name for Cloud SQL storage encryption. Empty when using platform-managed encryption."
  value = var.kms_key_name != "" ? var.kms_key_name : (
    length(google_kms_crypto_key.cloudsql) > 0 ? google_kms_crypto_key.cloudsql[0].id : ""
  )
}

output "private_vpc_connection" {
  description = "Service Networking connection Cloud SQL's private-IP mode peers through. A DatabaseInstance depends on this existing, not on any value it exposes."
  value       = google_service_networking_connection.cloudsql.id
}
