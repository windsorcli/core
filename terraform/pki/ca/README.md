---
title: pki/ca
description: Root CA generation (or BYO passthrough) for the private-CA add-on and Talos apiserver OIDC trust.
---

# pki/ca

Produces the root CA cert/key pair the `private-ca` PKI add-on and Talos's
`--oidc-ca-file` machine patch both consume. Supplying `cert`/`key` brings
your own CA and passes it straight through; leaving both empty generates a
new self-signed key/cert pair with the `tls` provider. Either way the
module's two outputs (`cert`, `key`) are the seam — downstream consumers
(the Talos machine config patch, the `private-ca-cert` Secret rendered by
the `pki` facet) don't need to know which path produced them.

Runs before `cluster/talos` so the CA is available for the apiserver's
OIDC trust flag at first bootstrap, rather than requiring a second apply
once cert-manager (or anything else inside the cluster) exists.

Root rotation is out-of-band when generated: unlike a cert-manager
`Certificate`, this module doesn't auto-renew, so rotating means forcing
recreation (e.g. bumping `validity_period_hours`) through a `windsor apply`.
A bring-your-own CA is expected to already have its own rotation process
upstream.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | 4.1.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.1.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [tls_private_key.ca](https://registry.terraform.io/providers/hashicorp/tls/4.1.0/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca](https://registry.terraform.io/providers/hashicorp/tls/4.1.0/docs/resources/self_signed_cert) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cert"></a> [cert](#input\_cert) | PEM-encoded CA certificate. Supply alongside key to bring your own; leave both empty to generate one. | `string` | `""` | no |
| <a name="input_common_name"></a> [common\_name](#input\_common\_name) | CA certificate common name (generated only, ignored when cert/key are supplied) | `string` | `"Private CA"` | no |
| <a name="input_key"></a> [key](#input\_key) | PEM-encoded CA private key. Supply alongside cert to bring your own; leave both empty to generate one. | `string` | `""` | no |
| <a name="input_validity_period_hours"></a> [validity\_period\_hours](#input\_validity\_period\_hours) | Certificate validity period in hours (generated only, ignored when cert/key are supplied) | `number` | `87600` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cert"></a> [cert](#output\_cert) | PEM-encoded CA certificate |
| <a name="output_key"></a> [key](#output\_key) | PEM-encoded CA private key |
<!-- END_TF_DOCS -->
