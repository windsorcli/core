---
title: provisioning/crossplane-iam
description: IAM and Pod Identity for Crossplane's AWS provider pods.
---

# provisioning/crossplane-iam

IAM role, policy, and EKS Pod Identity association per Crossplane-managed
AWS resource type, keyed by an internal catalog and `for_each` over
`resources`. Genuinely engine-specific: Pod Identity exists because a
Crossplane provider pod needs credentials to call AWS on the cluster's
behalf, a need no other database-creation mechanism shares. A second
Crossplane-managed AWS resource type means one new catalog entry here,
not a copy-pasted IAM block.

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
| [aws_eks_pod_identity_association.this](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/iam_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/data-sources/caller_identity) | data source |
| [aws_kms_key.secretsmanager_default](https://registry.terraform.io/providers/hashicorp/aws/6.58.0/docs/data-sources/kms_key) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the EKS cluster, scoping each role's trust policy to this cluster's Pod Identity Agent. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster the Pod Identity associations target. | `string` | n/a | yes |
| <a name="input_cluster_tag"></a> [cluster\_tag](#input\_cluster\_tag) | Value for the windsorcli.dev/cluster tag condition scoping each resource type's IAM policy. | `string` | n/a | yes |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_db_subnet_group_name"></a> [db\_subnet\_group\_name](#input\_db\_subnet\_group\_name) | Name of the DB subnet group rds:CreateDBInstance references, granted alongside the instance ARN it creates. | `string` | `""` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN the rds resource type's role may use for storage encryption. | `string` | `""` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Crossplane-managed AWS resource types to provision IAM and Pod Identity for. Supported: rds. | `set(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_role_arns"></a> [role\_arns](#output\_role\_arns) | Map of resource type to the IAM role ARN Crossplane assumes for it via Pod Identity. |
<!-- END_TF_DOCS -->
