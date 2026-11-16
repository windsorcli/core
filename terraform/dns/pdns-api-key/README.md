---
title: pdns-api-key
description: Generated API key for the in-cluster PowerDNS server and its external-dns provider.
---

Generates the key the `pdns` private DNS driver puts in the `pdns-api`
Secret. The stack only runs when `dns.private.pdns.api_key` is unset. A
supplied key replaces it.

Set `rotation` to any new string to generate a replacement key. PowerDNS and
external-dns read the key as an environment variable, so restart both after
the Secret updates.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.9.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [random_password.api_key](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_rotation"></a> [rotation](#input\_rotation) | Arbitrary string. Changing it generates a new API key. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_key"></a> [api\_key](#output\_api\_key) | Generated PowerDNS API key |
<!-- END_TF_DOCS -->
