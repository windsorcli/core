---
title: cloudflare
description: Cloudflare Tunnel, remote configuration, and wildcard DNS record for the external gateway.
---

Creates a remotely managed Cloudflare Tunnel that routes `*.<public_domain>`
to the external gateway Service, and the proxied wildcard `CNAME` that
points the hostnames at it. The module outputs the run token for
`cloudflared` as a sensitive value. The facet stores it in the
`tunnel-credentials` Secret.

The module reads `CLOUDFLARE_API_TOKEN` from the environment. The token
needs `Cloudflare Tunnel: Edit` and `DNS: Edit` on the zone, and it never
reaches the cluster.

The zone lookup uses `public_domain` as the zone name. Set `zone_name` when
`public_domain` is a subdomain of a zone in the account.

The origin connection is HTTPS with verification on. `origin_ca_pool` is the
path of the CA bundle that verifies the gateway certificate, and SNI
follows each request host.

Raise `secret_version` and apply to replace the tunnel secret. The tunnel,
its configuration, and the record are replaced create-before-destroy, so
existing connectors keep serving until they restart on the new token.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 5.29.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.9.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.29.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cloudflare_dns_record.wildcard](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs/resources/dns_record) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs/resources/zero_trust_tunnel_cloudflared) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared_config.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs/resources/zero_trust_tunnel_cloudflared_config) | resource |
| [random_id.tunnel_secret](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/id) | resource |
| [cloudflare_zero_trust_tunnel_cloudflared_token.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs/data-sources/zero_trust_tunnel_cloudflared_token) | data source |
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account that owns the tunnel. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the tunnel. | `string` | `"windsor"` | no |
| <a name="input_origin_ca_pool"></a> [origin\_ca\_pool](#input\_origin\_ca\_pool) | Path inside the connector to a PEM CA bundle that verifies the origin certificate. Null uses the system roots. | `string` | `null` | no |
| <a name="input_origin_service"></a> [origin\_service](#input\_origin\_service) | URL the tunnel forwards requests to. | `string` | n/a | yes |
| <a name="input_public_domain"></a> [public\_domain](#input\_public\_domain) | Domain the tunnel serves. Every hostname under it routes to the origin service. | `string` | n/a | yes |
| <a name="input_secret_version"></a> [secret\_version](#input\_secret\_version) | Version of the tunnel secret. Raising it replaces the secret and produces a new token. | `number` | `1` | no |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Cloudflare zone that holds public\_domain. Null uses public\_domain, which suits a domain that is itself a zone. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_tunnel_id"></a> [tunnel\_id](#output\_tunnel\_id) | ID of the Cloudflare Tunnel. |
| <a name="output_tunnel_token"></a> [tunnel\_token](#output\_tunnel\_token) | Run token for cloudflared. |
| <a name="output_wildcard_hostname"></a> [wildcard\_hostname](#output\_wildcard\_hostname) | Wildcard hostname the tunnel serves. |
<!-- END_TF_DOCS -->
