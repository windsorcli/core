<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.6.1 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [local_sensitive_file.kubeconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [null_resource.node_healthcheck](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [talos_cluster_kubeconfig.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster_kubeconfig) | resource |
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
| <a name="input_enable_health_check"></a> [enable\_health\_check](#input\_enable\_health\_check) | Whether to enable health checking for this node. | `bool` | `true` | no |
| <a name="input_endpoint"></a> [endpoint](#input\_endpoint) | The endpoint of the machine. | `string` | n/a | yes |
| <a name="input_extra_kernel_args"></a> [extra\_kernel\_args](#input\_extra\_kernel\_args) | Additional kernel arguments to pass to the machine. | `list(string)` | `[]` | no |
| <a name="input_image"></a> [image](#input\_image) | The Talos image to install. | `string` | `"ghcr.io/siderolabs/installer:latest"` | no |
| <a name="input_kubeconfig_path"></a> [kubeconfig\_path](#input\_kubeconfig\_path) | Path where the kubeconfig file should be written when bootstrap is true. | `string` | `""` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The Kubernetes version. | `string` | n/a | yes |
| <a name="input_machine_secrets"></a> [machine\_secrets](#input\_machine\_secrets) | The Talos machine secrets. | `any` | n/a | yes |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | The machine type, which must be either 'controlplane' or 'worker'. | `string` | n/a | yes |
| <a name="input_node"></a> [node](#input\_node) | The node address of the machine. | `string` | n/a | yes |
| <a name="input_skip_machine_config_apply"></a> [skip\_machine\_config\_apply](#input\_skip\_machine\_config\_apply) | When true, skip talos\_machine\_configuration\_apply (config already on the node via out-of-band delivery). | `bool` | `false` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The Talos version. | `string` | n/a | yes |
| <a name="input_talosconfig_path"></a> [talosconfig\_path](#input\_talosconfig\_path) | Path to the talosconfig file for health checking. | `string` | n/a | yes |
| <a name="input_wipe_disk"></a> [wipe\_disk](#input\_wipe\_disk) | Indicates whether to wipe the install disk. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | n/a |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | The generated kubeconfig when bootstrap is true |
| <a name="output_node"></a> [node](#output\_node) | n/a |
<!-- END_TF_DOCS -->