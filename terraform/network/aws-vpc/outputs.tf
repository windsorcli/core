#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "List of isolated subnet IDs"
  value       = aws_subnet.isolated[*].id
}

output "private_zone_id" {
  description = "ID of the VPC-attached private Route53 hosted zone created from var.domain_name. Null when no domain_name was supplied."
  value       = try(aws_route53_zone.main[0].zone_id, null)
}

output "private_zone_name" {
  description = "Name of the VPC-attached private Route53 hosted zone. Null when no domain_name was supplied."
  value       = try(aws_route53_zone.main[0].name, null)
}
