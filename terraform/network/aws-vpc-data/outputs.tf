output "vpc_id" {
  description = "The ID of the VPC"
  value       = data.aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = local.private_subnet_ids

  precondition {
    condition     = length(local.private_zones) >= 2
    error_message = "private_subnet_ids span ${length(local.private_zones)} availability zone(s); EKS needs at least 2."
  }
}

output "isolated_subnet_ids" {
  description = "List of isolated subnet IDs"
  value       = local.isolated_subnet_ids
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group spanning the isolated subnets. Null when no isolated subnets were supplied."
  value       = try(aws_db_subnet_group.main[0].name, null)
}

output "private_zone_id" {
  description = "ID of the supplied private Route53 hosted zone. Null when none was supplied."
  value       = try(data.aws_route53_zone.private[0].zone_id, null)
}

output "private_zone_name" {
  description = "Name of the supplied private Route53 hosted zone. Null when none was supplied."
  value       = try(data.aws_route53_zone.private[0].name, null)
}
