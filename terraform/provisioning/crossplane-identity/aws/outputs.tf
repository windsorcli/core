output "role_arns" {
  description = "Map of resource type to the IAM role ARN Crossplane assumes for it via Pod Identity."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
