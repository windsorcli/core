---
title: backend/s3
description: Creates the S3 bucket and KMS key Windsor uses as the Terraform remote state backend on AWS.
---

# backend/s3

Bootstraps Windsor's Terraform remote state backend on AWS. This module
creates an S3 bucket for state, a customer-managed KMS key for
encryption at rest, a hardened bucket policy (public-access-block,
SSE, versioning, lifecycle), and writes a `backend.tfvars` snippet
into the context so subsequent Terraform modules know where to read
and write state.

It runs first on `platform: aws` — every other AWS-side module
declares `dependsOn: backend` so the bucket exists before anything
tries to write to it.

The S3 backend uses native S3 locking (`use_lockfile = true` in the
generated backend config); no DynamoDB lock table is provisioned.

## Wiring

Wired by [platform-aws.yaml](../../../contexts/_template/facets/platform-aws.yaml).
The facet passes no explicit inputs; `context_path` and `context_id`
are auto-injected by the Windsor CLI based on the active context.

```yaml
terraform:
  - name: backend
    path: backend/s3
    # no inputs — context_path and context_id come from the CLI
```

The module's other variables (`s3_bucket_name`, `s3_log_bucket_name`,
`kms_key_alias`, `enable_kms`, `kms_policy_override`, `tags`,
`terraform_state_iam_roles`) are not driven by the facet and keep
their module defaults. Override any of them via tfvars (see
[Reference](#reference)) if you need a specific bucket name or to
target a centralized log bucket.

## Security

State encryption at rest uses a customer-managed KMS key
(`aws_kms_key.terraform_state`) created by this module; the alias is
the value of `kms_key_alias` (or a derived default when unset). The
bucket has versioning on, server-side encryption configured against
the KMS key, and a public-access-block that denies all public ACLs
and policies.

`force_destroy: true` is set unconditionally on the bucket. The
provider reads this flag from state at delete time, so it must be
true at apply time — not flipped only at destroy. The intent is that
`windsor destroy` can tear the bucket down with state still in it
without hitting `BucketNotEmpty`.

The bucket policy can grant additional principals via
`terraform_state_iam_roles` (a list of IAM role ARNs) or be replaced
wholesale by `kms_policy_override`. Both are unset by the facet —
defaults rely on the calling AWS principal (whoever runs
`windsor apply`) having direct bucket and KMS access.

Optional access logging: when `s3_log_bucket_name` is set, the module
emits `aws_s3_bucket_logging` against that pre-existing log bucket
(this module does not create the log bucket — point it at one created
elsewhere).

## See also

- [network/aws-vpc](../../network/aws-vpc/) — declares `dependsOn: backend` so the VPC's state lives in this bucket.
- [cluster/aws-eks](../../cluster/aws-eks/) — same pattern: depends on this module for the state backend.
- [backend/azurerm](../azurerm/) — sister module for Azure.
- [platform-aws.yaml](../../../contexts/_template/facets/platform-aws.yaml) — facet wiring.

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/backend.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.43.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.43.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [aws_kms_alias.terraform_state_alias](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/kms_alias) | resource |
| [aws_kms_key.terraform_state](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/resources/s3_bucket_versioning) | resource |
| [local_file.backend_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/6.43.0/docs/data-sources/region) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | `null` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder | `string` | `""` | no |
| <a name="input_enable_kms"></a> [enable\_kms](#input\_enable\_kms) | Provision a customer-managed KMS key and use SSE-KMS for the state bucket. False uses SSE-S3 (AES-256). | `bool` | `true` | no |
| <a name="input_kms_key_alias"></a> [kms\_key\_alias](#input\_kms\_key\_alias) | The KMS key ID for encrypting the S3 bucket | `string` | `""` | no |
| <a name="input_kms_policy_override"></a> [kms\_policy\_override](#input\_kms\_policy\_override) | Override for the KMS policy document (for testing) | `string` | `null` | no |
| <a name="input_s3_bucket_name"></a> [s3\_bucket\_name](#input\_s3\_bucket\_name) | The name of the S3 bucket for storing Terraform state, overrides the default bucket name | `string` | `""` | no |
| <a name="input_s3_log_bucket_name"></a> [s3\_log\_bucket\_name](#input\_s3\_log\_bucket\_name) | Name of a pre-existing, centralized S3 logging bucket to receive access logs. Must be created outside this module. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to resources (default is empty). | `map(string)` | `{}` | no |
| <a name="input_terraform_state_iam_roles"></a> [terraform\_state\_iam\_roles](#input\_terraform\_state\_iam\_roles) | List of IAM role ARNs that should have access to the Terraform state bucket | `list(string)` | `[]` | no |

### Outputs

No outputs.
<!-- END_TF_DOCS -->