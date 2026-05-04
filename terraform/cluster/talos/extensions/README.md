<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.11.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.2 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [null_resource.upgrade_controlplane](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.upgrade_worker](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [talos_image_factory_schematic.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/image_factory_schematic) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig and talosconfig are stored | `string` | `""` | no |
| <a name="input_controlplanes"></a> [controlplanes](#input\_controlplanes) | List of controlplane nodes to upgrade. Only node and endpoint are required. | <pre>list(object({<br/>    node     = string<br/>    endpoint = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extensions"></a> [extensions](#input\_extensions) | Talos Image Factory extension names to install (e.g. ["siderolabs/iscsi-tools"]). | `list(string)` | `[]` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The talos version to deploy. | `string` | n/a | yes |
| <a name="input_workers"></a> [workers](#input\_workers) | List of worker nodes to upgrade. Only node and endpoint are required. | <pre>list(object({<br/>    node     = string<br/>    endpoint = string<br/>  }))</pre> | `[]` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->