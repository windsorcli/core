---
title: AWS EC2
description: Launches Talos Linux nodes on EC2 at fixed private IPs for the metal platform.
---

Launches Talos Linux nodes as EC2 instances in an existing subnet. Each node
boots the published Talos AMI for `talos_version` at the private IP its
`cluster.controlplanes.nodes` or `cluster.workers.nodes` entry declares, so the
`metal` platform's `cluster/talos` step bootstraps them as it would bare-metal
machines. A shared security group opens the Talos API, the Kubernetes API and
NodePorts to the VPC CIDR. Root volumes are gp3, sized from each pool's
`root_disk_size`, `root_disk_iops` and `root_disk_throughput`, and encrypted
with a KMS key the module creates. Every resource carries the context id tag.
When `ephemeral` is true, resources also carry `windsorcli.dev/ephemeral` and a
fixed `windsorcli.dev/created-at` time for cleanup of short-lived nodes.

Enable it with `platform: metal` and `compute.driver: aws-ec2`. The AWS
provider authenticates from the context's ambient credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.68.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | 3.5.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.13 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.68.0 |
| <a name="provider_http"></a> [http](#provider\_http) | 3.5.0 |
| <a name="provider_time"></a> [time](#provider\_time) | ~> 0.13 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/instance) | resource |
| [aws_kms_alias.ebs](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/kms_alias) | resource |
| [aws_kms_key.ebs](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/kms_key) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/vpc_security_group_ingress_rule) | resource |
| [time_static.created](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/caller_identity) | data source |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/subnet) | data source |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/vpc) | data source |
| [http_http.talos_images](https://registry.terraform.io/providers/hashicorp/http/3.5.0/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment; used to name and tag resources. | `string` | `""` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder. | `string` | `""` | no |
| <a name="input_controlplane_instance_type"></a> [controlplane\_instance\_type](#input\_controlplane\_instance\_type) | EC2 instance type for control plane nodes. | `string` | n/a | yes |
| <a name="input_controlplane_root_volume"></a> [controlplane\_root\_volume](#input\_controlplane\_root\_volume) | gp3 root volume for control plane nodes: size in GB, IOPS and throughput in MB/s. | <pre>object({<br/>    size       = optional(number, 100)<br/>    iops       = optional(number, 3000)<br/>    throughput = optional(number, 125)<br/>  })</pre> | `{}` | no |
| <a name="input_controlplanes"></a> [controlplanes](#input\_controlplanes) | Control plane nodes to launch, each at its fixed private IP. | <pre>list(object({<br/>    hostname = string<br/>    node     = string<br/>  }))</pre> | n/a | yes |
| <a name="input_ephemeral"></a> [ephemeral](#input\_ephemeral) | Tags every resource as ephemeral with its creation time, for cleanup of short-lived nodes. | `bool` | `false` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region to launch the nodes in. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Existing subnet to launch the nodes in. Every node address must fall inside it. | `string` | n/a | yes |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Talos version whose published AMI the nodes boot, with or without a leading v. | `string` | n/a | yes |
| <a name="input_worker_instance_type"></a> [worker\_instance\_type](#input\_worker\_instance\_type) | EC2 instance type for worker nodes. Defaults to the control plane type. | `string` | `""` | no |
| <a name="input_worker_root_volume"></a> [worker\_root\_volume](#input\_worker\_root\_volume) | gp3 root volume for worker nodes: size in GB, IOPS and throughput in MB/s. | <pre>object({<br/>    size       = optional(number, 100)<br/>    iops       = optional(number, 3000)<br/>    throughput = optional(number, 125)<br/>  })</pre> | `{}` | no |
| <a name="input_workers"></a> [workers](#input\_workers) | Worker nodes to launch, each at its fixed private IP. | <pre>list(object({<br/>    hostname = string<br/>    node     = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ami_id"></a> [ami\_id](#output\_ami\_id) | AMI the nodes booted. |
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Control plane nodes in the shape cluster/talos consumes. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | KMS key that encrypts every node's root volume. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group attached to every node. |
| <a name="output_workers"></a> [workers](#output\_workers) | Worker nodes in the shape cluster/talos consumes. |
<!-- END_TF_DOCS -->
