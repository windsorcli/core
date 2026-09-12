---
title: provisioning/crossplane-identity/gcp
description: Workload Identity Federation for Crossplane's GCP provider pods.
---

# provisioning/crossplane-identity/gcp

Workload Identity for Crossplane's `provider-gcp-sql` pod — the GCP
counterpart to `provisioning/crossplane-identity/azure`'s federated
credential and `cluster/aws-eks`'s inline Pod Identity association. Binds
the provider pod's Kubernetes ServiceAccount to a dedicated Google Service
Account via `roles/iam.workloadIdentityUser`, then grants that service
account `roles/cloudsql.admin` — Google's own predefined least-privilege
role for this, since GCP's IAM model has no per-resource scoping to narrow
it further with a custom role the way Azure's RBAC does.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_google"></a> [google](#requirement\_google) | 8.2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_project_iam_member.this](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/project_iam_member) | resource |
| [google_service_account.this](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/service_account) | resource |
| [google_service_account_iam_member.workload_identity](https://registry.terraform.io/providers/hashicorp/google/8.2.0/docs/resources/service_account_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the GKE cluster, used to name each service account | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID the identities are created in | `string` | n/a | yes |
| <a name="input_resources"></a> [resources](#input\_resources) | Crossplane-managed GCP resource types to provision identity and IAM for. Supported: postgres. | `set(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_service_account_emails"></a> [service\_account\_emails](#output\_service\_account\_emails) | Map of resource type to the Google Service Account's email, for the Kubernetes ServiceAccount's iam.gke.io/gcp-service-account annotation. |
<!-- END_TF_DOCS -->
