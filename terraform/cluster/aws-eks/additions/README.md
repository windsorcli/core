<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 5.98.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 2.37.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.98.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 2.37.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_config_map.external_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/2.37.1/docs/resources/config_map) | resource |
| [kubernetes_namespace.system_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/2.37.1/docs/resources/namespace) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/5.98.0/docs/data-sources/caller_identity) | data source |
| [aws_eks_cluster.current](https://registry.terraform.io/providers/hashicorp/aws/5.98.0/docs/data-sources/eks_cluster) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/5.98.0/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_external_dns_role_arn"></a> [external\_dns\_role\_arn](#input\_external\_dns\_role\_arn) | ARN of the IAM role for external-dns. If not provided, will be looked up from the cluster. | `string` | `null` | no |
| <a name="input_route53_region"></a> [route53\_region](#input\_route53\_region) | AWS region where the Route53 hosted zone is located. If not provided, will use the cluster's region. | `string` | `null` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
