---
title: dns/zone/gcp-dns
description: DNS zone on Google Cloud DNS.
---

# dns/zone/gcp-dns

Creates a public Cloud DNS managed zone for a domain, independent of any
cluster — useful for zone-only deployments and for cases where DNS infra
has a different lifecycle than compute.

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

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_dns_managed_zone.main](https://registry.terraform.io/providers/hashicorp/google/8.1.0/docs/resources/dns_managed_zone) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. | `string` | `""` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | The fully-qualified domain name for the public managed zone (e.g. example.com). | `string` | n/a | yes |
| <a name="input_enable_dnssec"></a> [enable\_dnssec](#input\_enable\_dnssec) | Enable DNSSEC signing. Operator must publish the resulting DS record at the registrar. | `bool` | `false` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels applied to the managed zone. | `map(string)` | `{}` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID the managed zone is created in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | The fully-qualified domain name of the managed zone. |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | Authoritative name servers for the zone. Configure these as NS records at your domain registrar so public DNS queries resolve through this zone. |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | GCP project the zone lives in. Required by cert-manager (cloudDNS solver) and external-dns (google provider). |
| <a name="output_zone_name"></a> [zone\_name](#output\_zone\_name) | The GCP resource name of the managed zone. |
<!-- END_TF_DOCS -->
