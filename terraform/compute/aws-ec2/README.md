---
title: AWS EC2
description: Launches Talos Linux nodes on EC2 at fixed private IPs for the metal platform.
---

Launches Talos Linux nodes as EC2 instances in an existing subnet. Each node
boots the published Talos AMI for `talos_version` (or `ami_id`) at the private
IP its `cluster.controlplanes.nodes` or `cluster.workers.nodes` entry declares,
so the `metal` platform's `cluster/talos` step bootstraps them as it would
bare-metal machines. A shared security group opens the Talos API, the
Kubernetes API and NodePorts to `allowed_cidr`, which defaults to the VPC CIDR.

Enable it with `platform: metal` and `compute.driver: aws-ec2`. The AWS
provider authenticates from the context's ambient credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.68.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | 3.5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.68.0 |
| <a name="provider_http"></a> [http](#provider\_http) | 3.5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/subnet) | data source |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/vpc) | data source |
| [http_http.talos_images](https://registry.terraform.io/providers/hashicorp/http/3.5.0/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_cidr"></a> [allowed\_cidr](#input\_allowed\_cidr) | CIDR allowed to reach the Talos API, the Kubernetes API and NodePorts. Defaults to the VPC CIDR. | `string` | `""` | no |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI to boot instead of the published Talos AMI for talos\_version. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment; used to name and tag resources. | `string` | `""` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder. | `string` | `""` | no |
| <a name="input_controlplane_instance_type"></a> [controlplane\_instance\_type](#input\_controlplane\_instance\_type) | EC2 instance type for control plane nodes. | `string` | n/a | yes |
| <a name="input_controlplanes"></a> [controlplanes](#input\_controlplanes) | Control plane nodes to launch, each at its fixed private IP. | <pre>list(object({<br/>    hostname = string<br/>    node     = string<br/>  }))</pre> | n/a | yes |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key that encrypts the root volume. | `string` | `"alias/aws/ebs"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region to launch the nodes in. | `string` | n/a | yes |
| <a name="input_root_volume_iops"></a> [root\_volume\_iops](#input\_root\_volume\_iops) | Provisioned gp3 IOPS for the root volume. | `number` | `3000` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in GB. | `number` | `100` | no |
| <a name="input_root_volume_throughput"></a> [root\_volume\_throughput](#input\_root\_volume\_throughput) | Provisioned gp3 throughput for the root volume, in MB/s. | `number` | `125` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Existing subnet to launch the nodes in. Every node address must fall inside it. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for every resource. | `map(string)` | `{}` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Talos version whose published AMI the nodes boot, with or without a leading v. | `string` | n/a | yes |
| <a name="input_worker_instance_type"></a> [worker\_instance\_type](#input\_worker\_instance\_type) | EC2 instance type for worker nodes. Defaults to the control plane type. | `string` | `""` | no |
| <a name="input_workers"></a> [workers](#input\_workers) | Worker nodes to launch, each at its fixed private IP. | <pre>list(object({<br/>    hostname = string<br/>    node     = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ami_id"></a> [ami\_id](#output\_ami\_id) | AMI the nodes booted. |
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Control plane nodes in the shape cluster/talos consumes. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group attached to every node. |
| <a name="output_workers"></a> [workers](#output\_workers) | Worker nodes in the shape cluster/talos consumes. |
<!-- END_TF_DOCS -->
