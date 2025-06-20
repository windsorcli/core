<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 5.100.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.5.3 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_dynamodb_table.terraform_locks](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/dynamodb_table) | resource |
| [aws_kms_alias.terraform_state_alias](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/kms_alias) | resource |
| [aws_kms_key.terraform_state](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/s3_bucket_versioning) | resource |
| [local_file.backend_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | `null` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder | `string` | `""` | no |
| <a name="input_enable_dynamodb"></a> [enable\_dynamodb](#input\_enable\_dynamodb) | Feature flag to enable DynamoDB table creation | `bool` | `true` | no |
| <a name="input_enable_kms"></a> [enable\_kms](#input\_enable\_kms) | Feature flag to enable KMS encryption | `bool` | `true` | no |
| <a name="input_kms_key_alias"></a> [kms\_key\_alias](#input\_kms\_key\_alias) | The KMS key ID for encrypting the S3 bucket | `string` | `""` | no |
| <a name="input_kms_policy_override"></a> [kms\_policy\_override](#input\_kms\_policy\_override) | Override for the KMS policy document (for testing) | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | The AWS Region for the S3 Bucket and DynamoDB Table | `string` | `"us-east-2"` | no |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | The name of the S3 bucket for storing Terraform state, overrides the default bucket name | `string` | `""` | no |
| <a name="input_s3_log_bucket_name"></a> [s3\_log\_bucket\_name](#input\_s3\_log\_bucket\_name) | Name of a pre-existing, centralized S3 logging bucket to receive access logs. Must be created outside this module. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to resources (default is empty). | `map(string)` | `{}` | no |
| <a name="input_terraform_state_iam_roles"></a> [terraform\_state\_iam\_roles](#input\_terraform\_state\_iam\_roles) | List of IAM role ARNs that should have access to the Terraform state bucket | `list(string)` | `[]` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->