output "tunnel_id" {
  description = "ID of the Cloudflare Tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_token" {
  description = "Run token for cloudflared."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive   = true
}

output "wildcard_hostname" {
  description = "Wildcard hostname the tunnel serves."
  value       = cloudflare_dns_record.wildcard.name
}
