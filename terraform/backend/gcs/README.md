---
title: backend/gcs
description: Remote Terraform state on Google Cloud Storage.
---

# backend/gcs

Remote Terraform state for GCP contexts. The bootstrap pass runs this
module with a local backend, provisioning a GCS bucket; subsequent
applies use GCS's native object-generation locking — no separate lock
table.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_google"></a> [google](#requirement\_google) | 8.1.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.1.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_kms_crypto_key.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key_iam_member.gcs](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_kms_key_ring.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/kms_key_ring) | resource |
| [google_storage_bucket.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.terraform_state](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/storage_bucket_iam_member) | resource |
| [local_file.backend_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [google_storage_project_service_account.this](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the GCS bucket for storing Terraform state. If not provided, a default name will be generated | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | n/a | yes |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder | `string` | `""` | no |
| <a name="input_enable_cmek"></a> [enable\_cmek](#input\_enable\_cmek) | Encrypt the state bucket with a customer-managed KMS key instead of Google-managed encryption | `bool` | `false` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels to apply to resources | `map(string)` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | GCS bucket location for storing Terraform state | `string` | `"us-central1"` | no |
| <a name="input_log_bucket_name"></a> [log\_bucket\_name](#input\_log\_bucket\_name) | Name of a pre-existing, centralized GCS logging bucket to receive access logs. Must be created outside this module. | `string` | `""` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Object name prefix under which Terraform state is stored in the bucket | `string` | `"terraform/state"` | no |
| <a name="input_terraform_state_principals"></a> [terraform\_state\_principals](#input\_terraform\_state\_principals) | IAM members (e.g. "user:you@example.com", "serviceAccount:sa@project.iam.gserviceaccount.com") granted least-privilege access to read and write Terraform state objects in the bucket | `list(string)` | `[]` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
