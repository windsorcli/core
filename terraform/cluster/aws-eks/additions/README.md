---
title: cluster/aws-eks/additions
description: Post-cluster Kubernetes resources that link external-dns to its IAM role and Route53 region.
---

# cluster/aws-eks/additions

Post-cluster glue for [`cluster/aws-eks`](..). This module runs against the EKS API after the cluster is up and creates two Kubernetes resources used by the in-cluster [`dns` add-on](../../../../kustomize/dns/):

- `system-dns` namespace, labeled with `pod-security.kubernetes.io/{enforce,audit,warn} = baseline`.
- `external-dns` ConfigMap in that namespace, carrying `aws_region` (defaults to the cluster's region) and `txt_owner_id` (the cluster name) for external-dns's TXT registry.

The IAM role and Pod Identity association for external-dns are created by [`cluster/aws-eks`](..) itself; this module is the Kubernetes side of that wiring.

## Wiring

Wired by [platform-aws.yaml](../../../../contexts/_template/facets/platform-aws.yaml) immediately after the cluster module, with `destroy: false` so EKS deletion takes the namespace and ConfigMap with it (no orphaned API calls when the control plane is already torn down).

```yaml
terraform:
  - name: cluster-additions
    path: cluster/aws-eks/additions
    dependsOn:
      - cluster
    destroy: false
```

The facet passes no explicit inputs — `context_id` is auto-injected and `cluster_name` derives from it. Set `route53_region` via tfvars if your Route53 zone lives in a different region than the cluster.

## See also

- [cluster/aws-eks](../) — provisions the cluster, IAM role, and Pod Identity association this module's ConfigMap is consumed by.
- [`dns` add-on](../../../../kustomize/dns/) — the external-dns Helm release reads this ConfigMap.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/cluster-additions.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.43.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 3.1.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.43.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.1.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [kubernetes_config_map_v1.external_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/3.1.0/docs/resources/config_map_v1) | resource |
| [kubernetes_namespace_v1.system_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/3.1.0/docs/resources/namespace_v1) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/data-sources/region) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_external_dns_role_arn"></a> [external\_dns\_role\_arn](#input\_external\_dns\_role\_arn) | ARN of the IAM role for external-dns. If not provided, will be looked up from the cluster. | `string` | `null` | no |
| <a name="input_route53_region"></a> [route53\_region](#input\_route53\_region) | AWS region where the Route53 hosted zone is located. If not provided, will use the cluster's region. | `string` | `null` | no |

### Outputs

No outputs.
<!-- END_TF_DOCS -->
