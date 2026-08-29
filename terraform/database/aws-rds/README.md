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
| [aws_eks_pod_identity_association.secret_reader](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_policy.secret_reader](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/iam_policy) | resource |
| [aws_iam_role.secret_reader](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.secret_reader](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.rds](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/kms_alias) | resource |
| [aws_kms_key.rds](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/kms_key) | resource |
| [aws_security_group.rds](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/security_group) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/data-sources/caller_identity) | data source |
| [aws_kms_key.rds_default](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/data-sources/kms_key) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the EKS cluster, scoping the secret-reader role's trust policy to this cluster's Pod Identity Agent. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster the secret-reader role's Pod Identity association targets. | `string` | n/a | yes |
| <a name="input_cluster_security_group_id"></a> [cluster\_security\_group\_id](#input\_cluster\_security\_group\_id) | EKS cluster security group ID, allowed to reach RDS instances on the Postgres port. Attached to every node's ENI regardless of CNI driver. Pipe cluster/aws-eks's cluster\_security\_group\_id output. | `string` | `null` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Existing KMS key ARN for RDS storage encryption. Set to use a key you already manage instead of one this module creates. | `string` | `""` | no |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | The waiting period, specified in number of days, after which the KMS key is deleted. Valid values are 7-30. Default is 7. For compliance requirements (PCI DSS, SOC 2, HIPAA), 30 days is often required for critical keys to allow time for audit and recovery. | `number` | `7` | no |
| <a name="input_manage_encryption_key"></a> [manage\_encryption\_key](#input\_manage\_encryption\_key) | Whether to create a dedicated KMS key for RDS storage encryption. False falls back to the account's AWS-managed default key. | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC to create the RDS security group in. Pipe network/aws-vpc's vpc\_id output. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_kms_key_alias"></a> [kms\_key\_alias](#output\_kms\_key\_alias) | Alias name for the dedicated CMK, null when BYOK or the AWS-managed default key are in use |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | KMS key ARN for RDS storage encryption |
| <a name="output_secret_reader_role_arn"></a> [secret\_reader\_role\_arn](#output\_secret\_reader\_role\_arn) | IAM role ARN a bootstrap job in system-provisioning/rds-secret-reader assumes via Pod Identity to read RDS-managed master password secrets. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID with Postgres ingress restricted to this cluster's node security group. Reference from an Instance CR's vpcSecurityGroupIds. |
<!-- END_TF_DOCS -->
