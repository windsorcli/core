---
title: cluster/talos/config
description: Per-node Talos machine config + CIDATA seeds.
---

# cluster/talos/config

The before-compute stage for hypervisors with no metadata service or DHCP
(Hyper-V today). Generates the cluster identity, signs per-node machine
configs, and wraps each config plus its static-network cloud-init into a
CIDATA seed ISO that `compute/hyperv` attaches as the node's second DVD.
Exports the same identity back to `cluster/talos` so its bootstrap and
kubeconfig flow run without a redundant machine-config apply.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.12.0 |
| <a name="requirement_hyperv"></a> [hyperv](#requirement\_hyperv) | 0.3.1 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.11.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_hyperv"></a> [hyperv](#provider\_hyperv) | 0.3.1 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [hyperv_image_file.cidata](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/resources/image_file) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_secrets) | resource |
| [hyperv_iso_volume.cidata](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/data-sources/iso_volume) | data source |
| [talos_machine_configuration.controlplane](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.worker](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | Cluster control-plane API endpoint baked into every per-node machineconfig (e.g. https://<vip-or-cp1>:6443). Must be reachable from worker nodes once the cluster is up. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Talos cluster name. Must match what cluster/talos uses. | `string` | `"talos"` | no |
| <a name="input_common_config_patches"></a> [common\_config\_patches](#input\_common\_config\_patches) | Cluster-wide Talos machine config patch (YAML string). Same value cluster/talos consumes; applied to every node's machineconfig before CIDATA wrapping so the same patches reach the cluster regardless of delivery method. | `string` | `""` | no |
| <a name="input_context"></a> [context](#input\_context) | The windsor context id for this deployment. Typically set implicitly via TF\_VAR\_context. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Alias for var.context. | `string` | `""` | no |
| <a name="input_controlplane_config_patches"></a> [controlplane\_config\_patches](#input\_controlplane\_config\_patches) | Controlplane-only Talos machine config patch (YAML string). | `string` | `""` | no |
| <a name="input_controlplanes"></a> [controlplanes](#input\_controlplanes) | Per-node controlplane definitions. hostname/node mirror compute output and cluster.controlplanes.nodes shape; address is the static IP delivered via CIDATA's network-config. | <pre>list(object({<br/>    hostname = string<br/>    node     = string<br/>    address  = optional(string) # static IP in CIDR form (e.g. 192.168.0.10/22). Defaults to "${node}/${prefix}".<br/>  }))</pre> | `[]` | no |
| <a name="input_destination_dir"></a> [destination\_dir](#input\_destination\_dir) | Directory on the host where per-node CIDATA ISOs land. | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to install. Mirrors cluster/talos's default. | `string` | `"1.36.2"` | no |
| <a name="input_network"></a> [network](#input\_network) | Network config baked into each guest's CIDATA seed. cidr\_block's prefix length is reused when a node's address is unset. interface is a netplan name glob (default e* matches eth0 and enX0). | <pre>object({<br/>    cidr_block  = string<br/>    gateway     = string<br/>    nameservers = list(string)<br/>    interface   = optional(string, "e*")<br/>  })</pre> | n/a | yes |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Pinned Talos version (semver, no v-prefix). Used to call the secrets submodule and to stamp machineconfig templates. Must match the talos\_version cluster/talos consumes. | `string` | n/a | yes |
| <a name="input_worker_config_patches"></a> [worker\_config\_patches](#input\_worker\_config\_patches) | Worker-only Talos machine config patch (YAML string). | `string` | `""` | no |
| <a name="input_workers"></a> [workers](#input\_workers) | Per-node worker definitions. Same shape as controlplanes. | <pre>list(object({<br/>    hostname = string<br/>    node     = string<br/>    address  = optional(string)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cidata_iso_shas"></a> [cidata\_iso\_shas](#output\_cidata\_iso\_shas) | Per-node CIDATA ISO SHA-256 hashes (lowercase hex, host-on-disk values). Useful for cross-checking the on-host bytes match the runner-built bytes. |
| <a name="output_cidata_isos"></a> [cidata\_isos](#output\_cidata\_isos) | Per-node CIDATA ISO paths on the host. Keyed by hostname; values feed into compute/hyperv's instances[].cidata\_iso\_path so each VM gets the matching seed mounted as a second DVD. |
| <a name="output_client_configuration"></a> [client\_configuration](#output\_client\_configuration) | Talos client configuration (CA cert + admin cert/key). Pass to cluster/talos as var.client\_configuration so its talos\_client\_configuration data source can generate a working talosconfig file. |
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Pass-through of the controlplanes input, normalized with the resolved per-node address. |
| <a name="output_machine_secrets"></a> [machine\_secrets](#output\_machine\_secrets) | Talos cluster identity. Pass to cluster/talos as var.machine\_secrets so it shares the same cluster CA — cluster/talos then skips talos\_machine\_configuration\_apply (already delivered via CIDATA) and runs straight to bootstrap + kubeconfig + health checks. |
| <a name="output_workers"></a> [workers](#output\_workers) | Pass-through of the workers input, normalized with the resolved per-node address. |
<!-- END_TF_DOCS -->
