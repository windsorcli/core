#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

# Precedence: an explicitly supplied key, then the dedicated CMK this
# module creates, then the account's AWS-managed default key.
output "kms_key_arn" {
  description = "KMS key ARN for RDS storage encryption"
  value = var.kms_key_arn != "" ? var.kms_key_arn : (
    length(aws_kms_key.rds) > 0 ? aws_kms_key.rds[0].arn : data.aws_kms_key.rds_default[0].arn
  )
}

# Only set for the dedicated CMK this module creates; AWS managed keys and
# BYOK keys don't get an alias from this module.
output "kms_key_alias" {
  description = "Alias name for the dedicated CMK, null when BYOK or the AWS-managed default key are in use"
  value       = try(aws_kms_alias.rds[0].name, null)
}

output "security_group_id" {
  description = "Security group ID allowing Postgres access from anywhere in the VPC. Reference from an Instance CR's vpcSecurityGroupIds."
  value       = aws_security_group.rds.id
}

output "secret_reader_role_arn" {
  description = "IAM role ARN a bootstrap job in system-provisioning/rds-secret-reader assumes via Pod Identity to read RDS-managed master password secrets."
  value       = aws_iam_role.secret_reader.arn
}
