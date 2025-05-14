## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.8.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [talos_machine_bootstrap.bootstrap](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_bootstrap) | resource |
| [talos_machine_configuration_apply.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bootstrap"></a> [bootstrap](#input\_bootstrap) | Indicates whether to bootstrap the machine. | `bool` | `false` | no |
| <a name="input_client_configuration"></a> [client\_configuration](#input\_client\_configuration) | The Talos client configuration. | `any` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | The cluster endpoint. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | The name of the cluster. | `string` | n/a | yes |
| <a name="input_config_patches"></a> [config\_patches](#input\_config\_patches) | The configuration patches to apply to the machine. | `list(string)` | `[]` | no |
| <a name="input_disk_selector"></a> [disk\_selector](#input\_disk\_selector) | The disk selector to use for the machine. | <pre>object({<br/>    busPath  = string<br/>    modalias = string<br/>    model    = string<br/>    name     = string<br/>    serial   = string<br/>    size     = string<br/>    type     = string<br/>    uuid     = string<br/>    wwid     = string<br/>  })</pre> | `null` | no |
| <a name="input_endpoint"></a> [endpoint](#input\_endpoint) | The endpoint of the machine. | `string` | n/a | yes |
| <a name="input_extensions"></a> [extensions](#input\_extensions) | The extensions to use for the machine. | `list(object({ image = string }))` | `[]` | no |
| <a name="input_extra_kernel_args"></a> [extra\_kernel\_args](#input\_extra\_kernel\_args) | Additional kernel arguments to pass to the machine. | `list(string)` | `[]` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | The hostname of the machine. | `string` | `""` | no |
| <a name="input_image"></a> [image](#input\_image) | The Talos image to install. | `string` | `"ghcr.io/siderolabs/installer:latest"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The Kubernetes version. | `string` | n/a | yes |
| <a name="input_machine_secrets"></a> [machine\_secrets](#input\_machine\_secrets) | The Talos machine secrets. | `any` | n/a | yes |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | The machine type, which must be either 'controlplane' or 'worker'. | `string` | n/a | yes |
| <a name="input_node"></a> [node](#input\_node) | The node address of the machine. | `string` | n/a | yes |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The Talos version. | `string` | n/a | yes |
| <a name="input_wipe_disk"></a> [wipe\_disk](#input\_wipe\_disk) | Indicates whether to wipe the install disk. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | n/a |
| <a name="output_node"></a> [node](#output\_node) | n/a |
