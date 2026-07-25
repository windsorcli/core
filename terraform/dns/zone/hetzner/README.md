---
title: dns/zone/hetzner
description: Creates a primary Hetzner DNS zone via the official hcloud provider.
---

# dns/zone/hetzner

Creates a primary Hetzner DNS zone via the official hcloud provider. When
`parent_zone_name` names a zone in the same Hetzner account, it also creates the
NS delegation record in the parent so the subdomain resolves publicly with no
manual step. external-dns and cert-manager manage the records inside the zone.

Authenticates with the `HCLOUD_TOKEN` environment variable — DNS is part of the
Cloud API.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_hcloud"></a> [hcloud](#requirement\_hcloud) | 1.66.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_hcloud"></a> [hcloud](#provider\_hcloud) | 1.66.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [hcloud_zone.this](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/zone) | resource |
| [hcloud_zone_rrset.delegation](https://registry.terraform.io/providers/hetznercloud/hcloud/1.66.1/docs/resources/zone_rrset) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment; used to label the zone. | `string` | `""` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | DNS zone to create (e.g. hetzner.windsorcli.dev). | `string` | n/a | yes |
| <a name="input_hcloud_token"></a> [hcloud\_token](#input\_hcloud\_token) | Hetzner Cloud API token. Empty falls back to the HCLOUD\_TOKEN environment variable. | `string` | `""` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels for all resources. | `map(string)` | `{}` | no |
| <a name="input_parent_zone_name"></a> [parent\_zone\_name](#input\_parent\_zone\_name) | Parent DNS zone in the same Hetzner account to auto-create the NS delegation in (e.g. windsorcli.dev for domain\_name hetzner.windsorcli.dev). Empty skips delegation (manage it manually at the registrar). | `string` | `""` | no |
| <a name="input_ttl"></a> [ttl](#input\_ttl) | Default TTL (seconds) for the zone and the delegation records. | `number` | `3600` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nameservers"></a> [nameservers](#output\_nameservers) | Authoritative Hetzner nameservers assigned to the zone. Delegate these at the parent (automated when parent\_zone\_name is set). |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | Id of the created Hetzner DNS zone. |
| <a name="output_zone_name"></a> [zone\_name](#output\_zone\_name) | Name of the created zone. |
<!-- END_TF_DOCS -->
