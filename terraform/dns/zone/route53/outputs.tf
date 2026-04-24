#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "zone_id" {
  description = "The hosted zone ID. Consumed by cert-manager (ACME Route53 solver) and external-dns."
  value       = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "The authoritative name servers for the zone. Configure these as NS records at your domain registrar so public DNS queries resolve through this zone."
  value       = aws_route53_zone.main.name_servers
}

output "domain_name" {
  description = "The fully-qualified domain name of the hosted zone."
  value       = aws_route53_zone.main.name
}
