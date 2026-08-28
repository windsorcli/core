---
title: database/aws-rds
description: KMS encryption key for RDS storage, shared across every database in a context.
---

# database/aws-rds

The KMS key RDS storage encryption uses in this context. Creates a
dedicated CMK by default, with an `alias/<context_id>-rds` alias any
consumer (Crossplane-managed `Instance` CRs, or a future Terraform-native
database resource in this same module) can reference by name. Falls back
to the account's AWS-managed default key when `manage_encryption_key` is
false, or passes an operator-supplied `kms_key_arn` straight through.

One key per context, not one per database — shared by every RDS instance
regardless of how many exist or which mechanism creates them.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.58.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.58.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_kms_alias.rds](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/kms_alias) | resource |
| [aws_kms_key.rds](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/data-sources/caller_identity) | data source |
| [aws_kms_key.rds_default](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/data-sources/kms_key) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Existing KMS key ARN for RDS storage encryption. Set to use a key you already manage instead of one this module creates. | `string` | `""` | no |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | The waiting period, specified in number of days, after which the KMS key is deleted. Valid values are 7-30. Default is 7. For compliance requirements (PCI DSS, SOC 2, HIPAA), 30 days is often required for critical keys to allow time for audit and recovery. | `number` | `7` | no |
| <a name="input_manage_encryption_key"></a> [manage\_encryption\_key](#input\_manage\_encryption\_key) | Whether to create a dedicated KMS key for RDS storage encryption. False falls back to the account's AWS-managed default key. | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_kms_key_alias"></a> [kms\_key\_alias](#output\_kms\_key\_alias) | Alias name for the dedicated CMK, null when BYOK or the AWS-managed default key are in use |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | KMS key ARN for RDS storage encryption |
<!-- END_TF_DOCS -->
