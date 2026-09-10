---
title: database/gcp-cloudsql
description: Private service connection, KMS key, and admin credentials for Cloud SQL.
---

# database/gcp-cloudsql

Shared per-context infrastructure for Cloud SQL, not the database instance
itself — mirrors `database/aws-rds` and `database/azure-postgres`: a
Terraform-managed KMS key (BYOK-overridable), and here the Service
Networking private connection Cloud SQL's private-IP mode peers through,
the GCP equivalent of RDS's DB subnet group and Flexible Server's delegated
subnet.

Cloud SQL's own `User` resource has no auto-generate-and-write-to-Secret
mechanism for Postgres the way RDS's `Instance` and Flexible Server's own
resource do — `passwordSecretRef` only ever reads an existing Secret. This
module generates the password and writes it, one Secret per named instance
in `admin_credentials`, so the app-role/monitoring CronJob pattern stays
identical to RDS/Flexible Server's.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_google"></a> [google](#requirement\_google) | 8.2.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | 8.2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.2.0 |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | 8.2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.2.1 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google-beta_google_project_service_identity.cloudsql](https://registry.terraform.io/providers/hashicorp/google-beta/8.2.0/docs/resources/google_project_service_identity) | resource |
| [google_compute_global_address.private_service_connection](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/compute_global_address) | resource |
| [google_kms_crypto_key.cloudsql](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key_iam_member.cloudsql](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_kms_key_ring.cloudsql](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/kms_key_ring) | resource |
| [google_service_networking_connection.cloudsql](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/service_networking_connection) | resource |
| [kubernetes_namespace_v1.system_provisioning](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.admin_credentials](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [random_password.admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_credentials"></a> [admin\_credentials](#input\_admin\_credentials) | Admin credential Secrets to create, keyed by Cloud SQL instance name. Each entry generates a random password and writes it to <key>-admin-credentials in system-provisioning, the fixed name a chart's User CR reads via passwordSecretRef. | <pre>map(object({<br/>    username = string<br/>  }))</pre> | `{}` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Existing KMS CryptoKey resource name for Cloud SQL storage encryption. Set to use a key you already manage instead of one this module creates. | `string` | `""` | no |
| <a name="input_manage_encryption_key"></a> [manage\_encryption\_key](#input\_manage\_encryption\_key) | Whether to create a dedicated KMS key ring and key for Cloud SQL storage encryption. False falls back to Cloud SQL's platform-managed encryption. | `bool` | `true` | no |
| <a name="input_network_id"></a> [network\_id](#input\_network\_id) | ID of the VPC network Cloud SQL peers with for private IP connectivity. Pipe network/gcp-vpc's network\_id output. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID Cloud SQL is created in | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | GCP region for the KMS key ring | `string` | `"us-central1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_kms_key_name"></a> [kms\_key\_name](#output\_kms\_key\_name) | KMS CryptoKey resource name for Cloud SQL storage encryption. Null when using platform-managed encryption. |
| <a name="output_private_vpc_connection"></a> [private\_vpc\_connection](#output\_private\_vpc\_connection) | Service Networking connection Cloud SQL's private-IP mode peers through. A DatabaseInstance depends on this existing, not on any value it exposes. |
<!-- END_TF_DOCS -->
