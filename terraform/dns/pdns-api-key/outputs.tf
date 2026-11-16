output "api_key" {
  description = "Generated PowerDNS API key"
  value       = random_password.api_key.result
  sensitive   = true
}
