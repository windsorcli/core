---
title: Cloudflare
description: Looks up or creates a public Cloudflare zone.
---

Looks up a Cloudflare zone by name, or creates it when `create_zone` is true.
A created zone stays pending until the `name_servers` output is set at the
registrar. The module never changes zone settings. external-dns and
cert-manager manage the records inside the zone.

Authenticates with the `CLOUDFLARE_API_TOKEN` environment variable. Looking up
a zone needs `Zone:Read`. Creating one needs `Zone:Edit` on the account.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 5.29.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.29.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs/resources/zone) | resource |
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account that owns the zone. Required when create\_zone is true. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. | `string` | `""` | no |
| <a name="input_create_zone"></a> [create\_zone](#input\_create\_zone) | Create the zone. False looks up an existing zone. | `bool` | `false` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Name of the Cloudflare zone, for example example.com. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | The name of the zone. |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | The authoritative name servers for the zone. Set these at the domain registrar to activate a created zone. |
| <a name="output_status"></a> [status](#output\_status) | The zone status. A created zone is pending until the registrar delegates it. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | The zone ID. Consumed by external-dns as its zone filter. |
<!-- END_TF_DOCS -->