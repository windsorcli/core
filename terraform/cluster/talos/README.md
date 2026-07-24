---
title: cluster/talos
description: Self-hosted Kubernetes control plane via the Talos API.
---

# cluster/talos

Self-hosted Kubernetes control plane via the Talos API. Provisioning is
fully Terraform-driven through the Talos provider — no operator-side
`talosctl` calls. Nodes come up unprovisioned from `compute/<driver>`,
then `talos_machine_configuration_apply` pushes machine configs,
`talos_machine_bootstrap` initiates etcd election on the first control
plane, and `talos_cluster_kubeconfig` retrieves the kubeconfig once the
cluster is healthy. The `config/` submodule stamps per-node CIDATA
seeds; `extensions/` builds the Talos image with the required system
extensions baked in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.11.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_controlplane_bootstrap"></a> [controlplane\_bootstrap](#module\_controlplane\_bootstrap) | ./modules/machine | n/a |
| <a name="module_controlplanes"></a> [controlplanes](#module\_controlplanes) | ./modules/machine | n/a |
| <a name="module_workers"></a> [workers](#module\_workers) | ./modules/machine | n/a |

## Resources

| Name | Type |
|------|------|
| [local_sensitive_file.talosconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_secrets) | resource |
| [terraform_data.endpoint_check](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/client_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_client_configuration"></a> [client\_configuration](#input\_client\_configuration) | Pre-generated Talos client\_configuration (output of an upstream cluster/talos-secrets module). When null (default), cluster/talos derives it from the locally-generated talos\_machine\_secrets. Must be supplied together with machine\_secrets. | `any` | `null` | no |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | The external controlplane API endpoint (https://host:6443). If empty, derived from first controlplane's endpoint (Talos host:port → https://host:6443). | `string` | `"https://localhost:6443"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | The name of the cluster. | `string` | `"talos"` | no |
| <a name="input_common_config_patches"></a> [common\_config\_patches](#input\_common\_config\_patches) | A YAML string of common config patches to apply. Can be an empty string or valid YAML. | `string` | `""` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig and talosconfig are stored | `string` | `""` | no |
| <a name="input_controlplane_config_patches"></a> [controlplane\_config\_patches](#input\_controlplane\_config\_patches) | A YAML string of controlplane config patches to apply. Can be an empty string or valid YAML. | `string` | `""` | no |
| <a name="input_controlplane_disks"></a> [controlplane\_disks](#input\_controlplane\_disks) | Pool-level disks; used when a controlplane node has no disks key. Per-node disks override. | `list(any)` | `[]` | no |
| <a name="input_controlplane_volumes"></a> [controlplane\_volumes](#input\_controlplane\_volumes) | Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present). | `list(string)` | `[]` | no |
| <a name="input_controlplanes"></a> [controlplanes](#input\_controlplanes) | A list of machine configuration details for control planes. | <pre>list(object({<br/>    endpoint = string<br/>    node     = string<br/>    disks    = optional(list(any), [])<br/>    disk_selector = optional(object({<br/>      busPath  = optional(string)<br/>      modalias = optional(string)<br/>      model    = optional(string)<br/>      name     = optional(string)<br/>      serial   = optional(string)<br/>      size     = optional(string)<br/>      type     = optional(string)<br/>      uuid     = optional(string)<br/>      wwid     = optional(string)<br/>    }))<br/>    wipe_disk         = optional(bool, true)<br/>    extra_kernel_args = optional(list(string), [])<br/>    config_patches    = optional(string, "")<br/>  }))</pre> | `[]` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The kubernetes version to deploy. | `string` | `"1.36.2"` | no |
| <a name="input_machine_secrets"></a> [machine\_secrets](#input\_machine\_secrets) | Pre-generated Talos machine\_secrets (output of an upstream cluster/talos-secrets module). When null (default), cluster/talos generates its own. Must be supplied together with client\_configuration. | `any` | `null` | no |
| <a name="input_talos_node_image"></a> [talos\_node\_image](#input\_talos\_node\_image) | Literal Talos node image reference used to pin the image for mirror hydration. Kept in sync with talos\_version by Renovate. | `string` | `"ghcr.io/siderolabs/talos:v1.12.6"` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The talos version to deploy. Must match the node image tag (e.g. 1.12.1 for ghcr.io/siderolabs/talos:v1.12.1). | `string` | `"1.13.7"` | no |
| <a name="input_worker_config_patches"></a> [worker\_config\_patches](#input\_worker\_config\_patches) | A YAML string of worker config patches to apply. Can be an empty string or valid YAML. | `string` | `""` | no |
| <a name="input_worker_disks"></a> [worker\_disks](#input\_worker\_disks) | Pool-level disks; used when a worker node has no disks key. Per-node disks override. | `list(any)` | `[]` | no |
| <a name="input_worker_volumes"></a> [worker\_volumes](#input\_worker\_volumes) | Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present). | `list(string)` | `[]` | no |
| <a name="input_workers"></a> [workers](#input\_workers) | A list of machine configuration details | <pre>list(object({<br/>    endpoint = string<br/>    node     = string<br/>    disks    = optional(list(any), [])<br/>    disk_selector = optional(object({<br/>      busPath  = optional(string)<br/>      modalias = optional(string)<br/>      model    = optional(string)<br/>      name     = optional(string)<br/>      serial   = optional(string)<br/>      size     = optional(string)<br/>      type     = optional(string)<br/>      uuid     = optional(string)<br/>      wwid     = optional(string)<br/>    }))<br/>    wipe_disk         = optional(bool, true)<br/>    extra_kernel_args = optional(list(string), [])<br/>    config_patches    = optional(string, "")<br/>  }))</pre> | `[]` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
