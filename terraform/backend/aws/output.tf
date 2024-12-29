output "policy_arn" {
  value = aws_iam_policy.terraform_state.arn
}

output "bucket" {
  value = aws_s3_bucket.terraform_state.id
}

output "backend_tfvars" {
  value = local.backend_tfvars
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}

output "kms_key_alias" {
  value = aws_kms_alias.this.name
}
