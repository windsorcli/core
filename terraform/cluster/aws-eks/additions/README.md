---
title: cluster/aws-eks/additions
description: system-dns namespace and external-dns ConfigMap for EKS.
---

# cluster/aws-eks/additions

The in-cluster pieces external-dns needs on EKS: the `system-dns` namespace
(baseline Pod Security) and an `external-dns` ConfigMap carrying the Route53
region and TXT owner ID. Applied by `cluster/aws-eks` against the cluster's
Kubernetes API once the control plane is reachable.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.52.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 3.2.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.52.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [kubernetes_config_map_v1.external_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/3.2.1/docs/resources/config_map_v1) | resource |
| [kubernetes_namespace_v1.system_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/3.2.1/docs/resources/namespace_v1) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/6.52.0/docs/data-sources/region) | data source |

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
