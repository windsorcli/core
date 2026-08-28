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
