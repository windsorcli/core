output "cert" {
  description = "PEM-encoded CA certificate"
  value       = nonsensitive(local.cert_pem)

  precondition {
    condition     = local.cert_matches
    error_message = "cert does not match the generated CA key. Supply the chain signed from the csr output."
  }
}

output "key" {
  description = "PEM-encoded CA private key"
  value       = local.key_pem
  sensitive   = true
}

output "csr" {
  description = "PEM-encoded certificate signing request for the CA key"
  value       = tls_cert_request.ca.cert_request_pem
}
