## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 5.97.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.97.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.5.2 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eks_addon.main](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.main](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/eks_cluster) | resource |
| [aws_eks_fargate_profile.main](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/eks_fargate_profile) | resource |
| [aws_eks_node_group.main](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/eks_node_group) | resource |
| [aws_iam_policy.external_dns](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_policy) | resource |
| [aws_iam_policy.pod_identity_agent](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_policy) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role.efs_csi](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role.external_dns](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role.fargate](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role.node_group](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role.pod_identity_agent](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.efs_csi](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.external_dns](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.fargate_pod_execution_role_policy](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.pod_identity_agent](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_key.eks_encryption_key](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/kms_key) | resource |
| [aws_launch_template.node_group](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/launch_template) | resource |
| [aws_security_group.cluster_api_access](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/resources/security_group) | resource |
| [local_sensitive_file.kubeconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [null_resource.create_kubeconfig_dir](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/data-sources/caller_identity) | data source |
| [aws_eks_addon_version.default](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/data-sources/eks_addon_version) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/data-sources/region) | data source |
| [aws_subnets.private](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/data-sources/subnets) | data source |
| [aws_vpc.default](https://registry.terraform.io/providers/hashicorp/aws/5.97.0/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_addons"></a> [addons](#input\_addons) | Map of EKS add-ons | <pre>map(object({<br/>    version = optional(string)<br/>    tags    = optional(map(string), {})<br/>  }))</pre> | <pre>{<br/>  "aws-ebs-csi-driver": {},<br/>  "aws-efs-csi-driver": {},<br/>  "coredns": {},<br/>  "eks-pod-identity-agent": {},<br/>  "external-dns": {},<br/>  "vpc-cni": {}<br/>}</pre> | no |
| <a name="input_cluster_api_access_cidr_block"></a> [cluster\_api\_access\_cidr\_block](#input\_cluster\_api\_access\_cidr\_block) | The CIDR block for the cluster API access. | `string` | `"0.0.0.0/0"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | The name of the EKS cluster. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig is stored | `string` | `""` | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Whether to enable public access to the EKS cluster. | `bool` | `true` | no |
| <a name="input_fargate_profiles"></a> [fargate\_profiles](#input\_fargate\_profiles) | Map of EKS Fargate profile definitions to create. | <pre>map(object({<br/>    selectors = list(object({<br/>      namespace = string<br/>      labels    = optional(map(string), {})<br/>    }))<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The kubernetes version to deploy. | `string` | `"1.32"` | no |
| <a name="input_max_pods_per_node"></a> [max\_pods\_per\_node](#input\_max\_pods\_per\_node) | Maximum number of pods that can run on a single node | `number` | `64` | no |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Map of EKS managed node group definitions to create. | <pre>map(object({<br/>    instance_types = list(string)<br/>    min_size       = number<br/>    max_size       = number<br/>    desired_size   = number<br/>    disk_size      = optional(number, 64)<br/>    labels         = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = string<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | <pre>{<br/>  "default": {<br/>    "desired_size": 2,<br/>    "instance_types": [<br/>      "t3.medium"<br/>    ],<br/>    "max_size": 3,<br/>    "min_size": 1<br/>  }<br/>}</pre> | no |
| <a name="input_vpc_cni_config"></a> [vpc\_cni\_config](#input\_vpc\_cni\_config) | Configuration for the VPC CNI addon | <pre>object({<br/>    enable_prefix_delegation = bool<br/>    warm_prefix_target       = number<br/>    warm_ip_target           = number<br/>    minimum_ip_target        = number<br/>  })</pre> | <pre>{<br/>  "enable_prefix_delegation": true,<br/>  "minimum_ip_target": 1,<br/>  "warm_ip_target": 1,<br/>  "warm_prefix_target": 1<br/>}</pre> | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The ID of the VPC where the EKS cluster will be created. | `string` | `null` | no |

## Outputs

No outputs.
