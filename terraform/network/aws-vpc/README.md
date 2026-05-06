---
title: network/aws-vpc
description: Provisions the AWS VPC, subnets, NAT, and optional VPC-attached private Route53 zone that an EKS cluster sits on.
---

# network/aws-vpc

Provisions the AWS networking foundation for a Windsor cluster on EKS:
a VPC, three subnet tiers (public, private, isolated) per availability
zone, an Internet Gateway, NAT gateway(s), routing tables, and
(optionally) VPC flow logs and a VPC-attached private Route53 zone.
Its outputs are consumed by [`cluster/aws-eks`](../../cluster/aws-eks/)
(VPC + subnets), the [`lb-base` add-on](../../../kustomize/lb/) (VPC
ID for the AWS Load Balancer Controller), and external-dns when the
cluster runs in private-DNS mode (private zone ID).

## Wiring

Wired by [platform-aws.yaml](../../../contexts/_template/facets/platform-aws.yaml).
The facet only sets two inputs; the rest of the module's variables
(subnet sizing, NAT topology, flow logs, KMS) keep their module
defaults.

```yaml
terraform:
  - name: network
    path: network/aws-vpc
    dependsOn:
      - backend
    inputs:
      cidr_block: 10.0.0.0/16
      domain_name: prod.example.com    # optional
```

How those flow from `values.yaml`:

- `cidr_block` — `network.cidr_block`. Subnets are carved out of this CIDR; the default `subnet_newbits` and `availability_zones` settings on the module determine how.
- `domain_name` — `dns.private_domain`. When set, the module creates a VPC-attached `aws_route53_zone "main"` named after the domain. When unset, no private Route53 zone is created and `private_zone_id` / `private_zone_name` outputs are `null`.

The `backend` Terraform dep ensures the S3 state bucket exists before
this module's state is written. Locking is S3-native (`use_lockfile =
true`); no DynamoDB lock table is used.

## Security

VPC flow logs are on by default (`enable_flow_logs: true`). The module
also provisions a CloudWatch log group, an IAM role for the flow-logs
delivery, and (optionally) a customer-managed KMS key
(`create_flow_logs_kms_key: true`) used to encrypt the log group. The
default security group attached to the VPC has all rules revoked by
`aws_default_security_group "default"` — workloads must attach to
explicitly-defined security groups.

The private Route53 zone is created with `force_destroy: true` so
teardown removes the zone even if external-dns hasn't finished
deleting records before the cluster API goes down.

## See also

- [cluster/aws-eks](../../cluster/aws-eks/) — consumes `vpc_id` and `private_subnet_ids`.
- [`lb-base` add-on](../../../kustomize/lb/) — the AWS Load Balancer Controller consumes `vpc_id` to discover subnets and tag-based reconciliation scope.
- [`dns` add-on](../../../kustomize/dns/) — external-dns's Route 53 provider consumes `private_zone_id` when running in private-DNS mode (`gateway.access: private`).
- [platform-aws.yaml](../../../contexts/_template/facets/platform-aws.yaml) — facet wiring.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/network.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.43.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.43.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.vpc_flow_logs](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.default](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/eip) | resource |
| [aws_flow_log.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/flow_log) | resource |
| [aws_iam_role.vpc_flow_logs](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.vpc_flow_logs](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/internet_gateway) | resource |
| [aws_kms_alias.vpc_flow_logs](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/kms_alias) | resource |
| [aws_kms_key.vpc_flow_logs](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/kms_key) | resource |
| [aws_nat_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/nat_gateway) | resource |
| [aws_route53_zone.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route53_zone) | resource |
| [aws_route_table.isolated](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route_table) | resource |
| [aws_route_table_association.isolated](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route_table_association) | resource |
| [aws_subnet.isolated](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/vpc) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/data-sources/region) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Number of availability zones to use for the subnets | `number` | `3` | no |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_create_flow_logs_kms_key"></a> [create\_flow\_logs\_kms\_key](#input\_create\_flow\_logs\_kms\_key) | Create a KMS key for flow logs | `bool` | `true` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The domain name for the Route53 hosted zone | `string` | `null` | no |
| <a name="input_enable_dns_hostnames"></a> [enable\_dns\_hostnames](#input\_enable\_dns\_hostnames) | Enable DNS hostnames in the VPC | `bool` | `true` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Enable DNS support in the VPC | `bool` | `true` | no |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Whether to provision VPC flow logs (the aws\_flow\_log resource, its CloudWatch log group, and the IAM role that publishes to it). | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Enable NAT Gateway for private subnets | `bool` | `true` | no |
| <a name="input_flow_logs_kms_key_id"></a> [flow\_logs\_kms\_key\_id](#input\_flow\_logs\_kms\_key\_id) | The KMS key ID for flow logs | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for all resources in the VPC | `string` | `""` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Use a single NAT Gateway for all private subnets | `bool` | `false` | no |
| <a name="input_subnet_newbits"></a> [subnet\_newbits](#input\_subnet\_newbits) | Number of new bits for the subnet | `number` | `4` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags for all resources | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_isolated_subnet_ids"></a> [isolated\_subnet\_ids](#output\_isolated\_subnet\_ids) | List of isolated subnet IDs |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | List of private subnet IDs |
| <a name="output_private_zone_id"></a> [private\_zone\_id](#output\_private\_zone\_id) | ID of the VPC-attached private Route53 hosted zone created from var.domain\_name. Null when no domain\_name was supplied. |
| <a name="output_private_zone_name"></a> [private\_zone\_name](#output\_private\_zone\_name) | Name of the VPC-attached private Route53 hosted zone. Null when no domain\_name was supplied. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | List of public subnet IDs |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC |
<!-- END_TF_DOCS -->