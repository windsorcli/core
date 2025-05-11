output "bucket" {
  description = "The name of the S3 bucket used for storing Terraform state"
  value       = aws_s3_bucket.this.id
}

output "dynamodb_table" {
  description = "The name of the DynamoDB table used for state locking"
  value       = var.enable_dynamodb ? aws_dynamodb_table.terraform_locks[0].name : null
}

output "kms_key_arn" {
  description = "The ARN of the KMS key using the alias for encrypting the S3 bucket"
  value       = (var.enable_kms && var.kms_key_alias == "") ? aws_kms_alias.terraform_state_alias[0].arn : null
}

output "region" {
  description = "The AWS Region of the S3 Bucket and DynamoDB Table"
  value       = var.region
}
