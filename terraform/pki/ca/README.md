---
title: CA
description: Root CA generation (or BYO passthrough) for the private-CA add-on and Talos apiserver OIDC trust.
---

Produces the cluster CA cert/key pair the `private-ca` PKI add-on and Talos's
`--oidc-ca-file` machine patch both consume, plus a `csr` for that key. The
module always outputs `cert`, `key`, and `csr`, whichever inputs are set:

| `cert` | `key` | Result |
|---|---|---|
| empty | empty | Generates a key and a self-signed certificate. |
| set | empty | Keeps the generated key and outputs the supplied chain. |
| set | set | Passes a brought-your-own CA straight through. |

A site PKI team signs `csr` to place the cluster CA under its own root. The
operator then sets `cert` to the signed chain, CA certificate first, and
applies again. The key stays in state, so the CA keeps its key across the
switch. The module rejects a chain whose first certificate does not carry the
generated public key. The CSR has no name-constraint extension, because the
`tls` provider cannot add one, so the signer MUST apply any constraint on
`dns.private_domain` itself.

Runs before `cluster/talos` so the CA is available for the apiserver's
OIDC trust flag at first bootstrap, rather than requiring a second apply
once cert-manager (or anything else inside the cluster) exists.

Root rotation is out-of-band when generated: unlike a cert-manager
`Certificate`, this module doesn't auto-renew, so rotating means forcing
recreation (e.g. bumping `validity_period_hours`) through a `windsor apply`.
A signed or brought-your-own CA follows its signer's rotation process.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | 4.4.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.4.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [tls_cert_request.ca](https://registry.terraform.io/providers/hashicorp/tls/4.4.1/docs/resources/cert_request) | resource |
| [tls_private_key.ca](https://registry.terraform.io/providers/hashicorp/tls/4.4.1/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca](https://registry.terraform.io/providers/hashicorp/tls/4.4.1/docs/resources/self_signed_cert) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cert"></a> [cert](#input\_cert) | PEM-encoded CA certificate chain. Supply alone to use a signed copy of csr, with key to bring your own CA, or leave empty to self-sign. | `string` | `""` | no |
| <a name="input_common_name"></a> [common\_name](#input\_common\_name) | CA certificate common name (subject of the self-signed certificate and the CSR) | `string` | `"Private CA"` | no |
| <a name="input_key"></a> [key](#input\_key) | PEM-encoded CA private key. Supply with cert to bring your own CA, or leave empty to generate one. | `string` | `""` | no |
| <a name="input_validity_period_hours"></a> [validity\_period\_hours](#input\_validity\_period\_hours) | Self-signed certificate validity period in hours (ignored when cert is supplied) | `number` | `87600` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cert"></a> [cert](#output\_cert) | PEM-encoded CA certificate |
| <a name="output_csr"></a> [csr](#output\_csr) | PEM-encoded certificate signing request for the CA key |
| <a name="output_key"></a> [key](#output\_key) | PEM-encoded CA private key |
<!-- END_TF_DOCS -->
