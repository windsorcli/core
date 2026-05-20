---
title: dns/zone/route53
description: Provisions a public Route53 hosted zone for cert-manager ACME and external-dns, with optional DNSSEC and query logging.
---

# dns/zone/route53

Creates a public Route53 hosted zone for a domain. Kept independent
of any network/cluster module so a domain can be provisioned
standalone — useful for zone-only deployments and for cases where DNS
infra has a different lifecycle than compute.

The zone is consumed by:

- **cert-manager (Route53 ACME solver)** — DNS-01 challenges for Let's Encrypt certificates issued via the `public` ClusterIssuer.
- **external-dns** — automatic publication of Gateway / Service hostnames as Route53 records.

After apply, point your domain registrar at the `name_servers` output
so public DNS queries resolve through this zone. The `zone_id` output
feeds [`cluster/aws-eks`](../../../cluster/aws-eks/)'s
`cert_manager_hosted_zone_ids` so the cert-manager IAM policy is
scoped to just this zone.

`force_destroy` is set to `true` unconditionally so `windsor destroy`
can tear the zone down even when it still has records (ACME challenge
TXTs, external-dns entries) — the AWS provider reads `force_destroy`
from state at delete time, so it has to be persisted from apply.
Matches the [`backend/s3`](../../../backend/s3/) bucket pattern.

## Wiring

Wired by [platform-aws.yaml](../../../../contexts/_template/facets/platform-aws.yaml). The facet only emits this entry when the operator sets `dns.public_domain`.

```yaml
terraform:
  - name: dns-zone
    path: dns/zone/route53
    when: "(dns.public_domain ?? '') != ''"
    inputs:
      domain_name: <dns.public_domain>
```

How those flow from `values.yaml`:

- `domain_name` — `dns.public_domain`. Required; the zone is named after this domain.

## DNSSEC (`enable_dnssec`)

Off by default. When enabled, provisions a us-east-1 KSK KMS key
(`ECC_NIST_P256` / `SIGN_VERIFY`), an `aws_route53_key_signing_key`,
and `aws_route53_hosted_zone_dnssec` set to `SIGNING`. Route53 only
accepts KSK keys from us-east-1 — that's why the module pins a
`us_east_1` provider alias regardless of the deployment region.

After apply, publish the DS record at the domain registrar — the
`ds_record` output exposes `key_tag`, `signing_algorithm_mnemonic`,
`digest_algorithm_mnemonic`, `digest_value`, and the formatted
`ds_record` string. Until that NS-side handoff completes, DNSSEC-
validating resolvers will fail to resolve the zone, so don't enable
this without coordinating with whoever controls the registrar.

## Query logging (`enable_query_logging`)

Off by default. When enabled, provisions a CloudWatch log group at
`/aws/route53/<domain>` in us-east-1 (Route53 only delivers query
logs to us-east-1), a resource policy granting Route53
`logs:CreateLogStream` / `logs:PutLogEvents`, and an
`aws_route53_query_log` binding. Retention defaults to 30 days and is
configurable via `query_log_retention_days`. CloudWatch ingestion
plus storage cost scales with query volume.

## See also

- [`cluster/aws-eks`](../../../cluster/aws-eks/) — consumes `zone_id` via the facet's `cert_manager_hosted_zone_ids` input to scope the cert-manager IAM policy to just this zone.
- [`dns/zone/azure-dns`](../azure-dns/) — sister module for Azure.
- [platform-aws.yaml](../../../../contexts/_template/facets/platform-aws.yaml) — facet wiring.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/dns-zone.tfvars`.

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
| <a name="provider_aws.us_east_1"></a> [aws.us\_east\_1](#provider\_aws.us\_east\_1) | 6.43.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.query_log](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.query_log](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_kms_key.dnssec](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/kms_key) | resource |
| [aws_route53_hosted_zone_dnssec.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route53_hosted_zone_dnssec) | resource |
| [aws_route53_key_signing_key.dnssec](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route53_key_signing_key) | resource |
| [aws_route53_query_log.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route53_query_log) | resource |
| [aws_route53_zone.main](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/route53_zone) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/data-sources/caller_identity) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The fully-qualified domain name for the public hosted zone (e.g. example.com). | `string` | n/a | yes |
| <a name="input_enable_dnssec"></a> [enable\_dnssec](#input\_enable\_dnssec) | Enable DNSSEC signing. Operator must publish the DS record (see ds\_record output) at the registrar. | `bool` | `false` | no |
| <a name="input_enable_query_logging"></a> [enable\_query\_logging](#input\_enable\_query\_logging) | Enable Route53 query logging to a CloudWatch log group in us-east-1. | `bool` | `false` | no |
| <a name="input_query_log_retention_days"></a> [query\_log\_retention\_days](#input\_query\_log\_retention\_days) | Retention (days) for the query log group. Ignored when enable\_query\_logging is false. | `number` | `30` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to the hosted zone. | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | The fully-qualified domain name of the hosted zone. |
| <a name="output_ds_record"></a> [ds\_record](#output\_ds\_record) | DS record fields to publish at the registrar when DNSSEC is enabled. Null when disabled. |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | The authoritative name servers for the zone. Configure these as NS records at your domain registrar so public DNS queries resolve through this zone. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | The hosted zone ID. Consumed by cert-manager (ACME Route53 solver) and external-dns. |
<!-- END_TF_DOCS -->
