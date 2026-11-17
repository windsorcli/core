---
title: network/aws-vpc-data
description: Reads an existing VPC and its subnets for EKS.
---

# network/aws-vpc-data

Reads a VPC and subnets that someone else owns and emits the same
outputs as [network/aws-vpc](../aws-vpc/), so `cluster/aws-eks` and the
database modules consume it unchanged. The `platform-aws` facet selects
it when `network.existing.id` is set. The only resource it creates is
the RDS DB subnet group over `isolated_subnet_ids`, a grouping that
leaves the subnets untouched. `windsor destroy` leaves the VPC and
subnets in place.

Plan fails when:

- a supplied subnet belongs to a different VPC.
- `private_subnet_ids` is empty or spans fewer than two availability zones.
- `isolated_subnet_ids` is set and spans fewer than two availability zones.

The network owner keeps responsibility for NAT or other egress, flow
logs, the default security group, and the private Route53 zone. Size
the private subnets for nodes plus pods, since the VPC CNI gives every
pod a subnet address.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.68.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.68.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_db_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/db_subnet_group) | resource |
| [aws_route53_zone.private](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/route53_zone) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/subnet) | data source |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_isolated_subnet_ids"></a> [isolated\_subnet\_ids](#input\_isolated\_subnet\_ids) | IDs of existing subnets that hold databases. The DB subnet group spans them when set. | `list(string)` | `[]` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | IDs of existing subnets that hold cluster nodes | `list(string)` | n/a | yes |
| <a name="input_private_zone_id"></a> [private\_zone\_id](#input\_private\_zone\_id) | ID of an existing private Route53 hosted zone to pass through as private\_zone\_id | `string` | `null` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | IDs of existing subnets that serve as the public tier | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for the resources this module creates | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the existing VPC | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_db_subnet_group_name"></a> [db\_subnet\_group\_name](#output\_db\_subnet\_group\_name) | Name of the DB subnet group spanning the isolated subnets. Null when no isolated subnets were supplied. |
| <a name="output_isolated_subnet_ids"></a> [isolated\_subnet\_ids](#output\_isolated\_subnet\_ids) | List of isolated subnet IDs |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | List of private subnet IDs |
| <a name="output_private_zone_id"></a> [private\_zone\_id](#output\_private\_zone\_id) | ID of the supplied private Route53 hosted zone. Null when none was supplied. |
| <a name="output_private_zone_name"></a> [private\_zone\_name](#output\_private\_zone\_name) | Name of the supplied private Route53 hosted zone. Null when none was supplied. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | List of public subnet IDs |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC |
<!-- END_TF_DOCS -->
