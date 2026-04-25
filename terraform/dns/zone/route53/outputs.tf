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

output "ds_record" {
  description = "DS record fields to publish at the registrar when DNSSEC is enabled. Null when disabled."
  value = var.enable_dnssec ? {
    key_tag                    = aws_route53_key_signing_key.dnssec[0].key_tag
    signing_algorithm_mnemonic = aws_route53_key_signing_key.dnssec[0].signing_algorithm_mnemonic
    digest_algorithm_mnemonic  = aws_route53_key_signing_key.dnssec[0].digest_algorithm_mnemonic
    digest_value               = aws_route53_key_signing_key.dnssec[0].digest_value
    ds_record                  = aws_route53_key_signing_key.dnssec[0].ds_record
  } : null
}
