output "cert" {
  description = "PEM-encoded CA certificate"
  value       = nonsensitive(local.byo ? var.cert : tls_self_signed_cert.ca[0].cert_pem)
}

output "key" {
  description = "PEM-encoded CA private key"
  value       = local.byo ? var.key : tls_private_key.ca[0].private_key_pem
  sensitive   = true
}
