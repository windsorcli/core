---
title: cluster/talos
description: Generates Talos machine secrets and applies machine configuration to existing controlplane and worker nodes.
---

# cluster/talos

Configures and bootstraps a Talos Kubernetes cluster on top of nodes
that are already running. This module does **not** provision the nodes
— that's [`compute/docker`](../../compute/docker/) /
[`compute/incus`](../../compute/incus/) on workstation platforms, or
external infrastructure on metal. Given a list of controlplane and
worker endpoints, this module generates a cluster CA, applies Talos
machine configuration to each node, bootstraps etcd on the first
controlplane, and writes `talosconfig` + `kubeconfig` to the context
directory.

After this module finishes, the cluster has Kubernetes running but no
CNI (the `flannel` default is disabled when Cilium is the chosen CNI;
Talos's built-in flannel runs otherwise on Talos clusters that don't
opt out). [`cni/cilium`](../../cni/) installs Cilium next on Talos
clusters; [`gitops/flux`](../../gitops/flux/) follows.

## Wiring

Wired by every Talos platform — `platform-metal`, `platform-docker`,
`platform-incus`. Each platform passes its own controlplane / worker
node list; the rest of the inputs are common, sourced from `talos_common`
(an internal config object built from `cluster.*` schema fields by
[config-talos.yaml](../../../contexts/_template/facets/config-talos.yaml)).

Typical materialization on a metal cluster:

```yaml
terraform:
  - name: cluster
    path: cluster/talos
    parallelism: 1
    inputs:
      cluster_endpoint: https://10.5.0.10:6443
      cluster_name: talos
      talos_version: 1.12.6
      controlplanes:
        - hostname: controlplane-1
          endpoint: 10.5.0.10:50000
          node: 10.5.0.10
      workers:
        - hostname: worker-1
          endpoint: 10.5.0.20:50000
          node: 10.5.0.20
      common_config_patches: |
        cluster:
          allowSchedulingOnControlPlanes: false
          ...
      controlplane_disks: []
      worker_disks: []
```

How the inputs flow from `values.yaml`:

- `controlplanes` / `workers` — `cluster.controlplanes.nodes` and `cluster.workers.nodes`. Each entry needs `hostname`, `endpoint` (Talos API, typically `<ip>:50000`), and `node` (the node's IP). On workstation platforms the values come from the `compute` module's terraform output; on metal you author them directly.
- `cluster_endpoint` — `cluster.endpoint`. Optional. When unset, derived from the first controlplane's endpoint (rewritten to `https://<host>:6443`).
- `cluster_name` — facet-set to `talos`. Not exposed.
- `talos_version` — pinned in [config-talos.yaml](../../../contexts/_template/facets/config-talos.yaml) (`talos.talos_version`); Renovate maintains it. Not a typical user knob.
- `common_config_patches` — facet-built. The merged Talos machine patch fed by `cluster.controlplanes.schedulable`, `cluster.driver`, `topology`, the chosen CNI, and a few baked-in defaults (kubelet cert rotation, etcd auto-compaction on single-node). Single string of YAML; not edited directly.
- `controlplane_disks` / `worker_disks` — `cluster.controlplanes.disks` / `cluster.workers.disks`. When unset and the storage driver is Longhorn, defaults to a single 30 GiB disk named `longhorn`; otherwise empty.
- `controlplane_volumes` / `worker_volumes` — `cluster.controlplanes.volumes` / `cluster.workers.volumes`. Raw mount paths; rendered into Talos `extraMounts` for kubelet.
- `kubernetes_version` — module default; not currently flowed through the facets.
- `controlplane_config_patches`, `worker_config_patches` — module defaults; not currently flowed through the facets.

`parallelism: 1` is set on every platform's wiring because Talos
machine secrets and the etcd bootstrap are both single-writer
operations — running the controlplane modules in parallel races etcd
init.

## Security

Generates `talos_machine_secrets` (the cluster CA and Talos node
identity material). The CA is held in Terraform state — protect the
state backend accordingly. Re-creating this resource issues a new CA;
on container-backed compute (docker, incus) where Talos state is
stored in a node volume, the volumes must be removed before re-apply,
otherwise nodes still hold the old CA and the TLS handshake fails
(this is why the module has a destroy-and-recreate hazard documented
on the `talos_machine_secrets` resource).

`talosconfig` is written to `${context_path}/.talos/config` with mode
`0600`. The `./modules/machine` submodule writes `kubeconfig` to
`${context_path}/.kube/config`, also `0600`. Both contain credentials
that can administer the cluster.

## See also

- [compute/docker](../../compute/docker/) and [compute/incus](../../compute/incus/) — provision the Talos nodes that this module then configures.
- [cni/cilium](../../cni/cilium/) — runs after this module to install pod networking.
- [gitops/flux](../../gitops/flux/) — runs after CNI to install Flux.
- [cluster/talos/extensions](extensions/) — Talos Image Factory extensions catalog (used to compose node images with required modules like `iscsi-tools` for Longhorn).
- [config-talos.yaml](../../../contexts/_template/facets/config-talos.yaml) — facet that builds `talos_common` (the merged Talos machine patch source).
- Talos documentation — https://www.talos.dev/

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/cluster.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.11.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.6.1 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_controlplane_bootstrap"></a> [controlplane\_bootstrap](#module\_controlplane\_bootstrap) | ./modules/machine | n/a |
| <a name="module_controlplanes"></a> [controlplanes](#module\_controlplanes) | ./modules/machine | n/a |
| <a name="module_workers"></a> [workers](#module\_workers) | ./modules/machine | n/a |

### Resources

| Name | Type |
|------|------|
| [local_sensitive_file.talosconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_secrets) | resource |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/client_configuration) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | The external controlplane API endpoint (https://host:6443). If empty, derived from first controlplane's endpoint (Talos host:port → https://host:6443). | `string` | `"https://localhost:6443"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | The name of the cluster. | `string` | `"talos"` | no |
| <a name="input_common_config_patches"></a> [common\_config\_patches](#input\_common\_config\_patches) | A YAML string of common config patches to apply. Can be an empty string or valid YAML. | `string` | `""` | no |
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig and talosconfig are stored | `string` | `""` | no |
| <a name="input_controlplane_config_patches"></a> [controlplane\_config\_patches](#input\_controlplane\_config\_patches) | A YAML string of controlplane config patches to apply. Can be an empty string or valid YAML. | `string` | `""` | no |
| <a name="input_controlplane_disks"></a> [controlplane\_disks](#input\_controlplane\_disks) | Pool-level disks; used when a controlplane node has no disks key. Per-node disks override. | `list(any)` | `[]` | no |
| <a name="input_controlplane_volumes"></a> [controlplane\_volumes](#input\_controlplane\_volumes) | Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present). | `list(string)` | `[]` | no |
| <a name="input_controlplanes"></a> [controlplanes](#input\_controlplanes) | A list of machine configuration details for control planes. | <pre>list(object({<br/>    endpoint = string<br/>    node     = string<br/>    disks    = optional(list(any), [])<br/>    disk_selector = optional(object({<br/>      busPath  = optional(string)<br/>      modalias = optional(string)<br/>      model    = optional(string)<br/>      name     = optional(string)<br/>      serial   = optional(string)<br/>      size     = optional(string)<br/>      type     = optional(string)<br/>      uuid     = optional(string)<br/>      wwid     = optional(string)<br/>    }))<br/>    wipe_disk         = optional(bool, true)<br/>    extra_kernel_args = optional(list(string), [])<br/>    config_patches    = optional(string, "")<br/>  }))</pre> | `[]` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The kubernetes version to deploy. | `string` | `"1.35.4"` | no |
| <a name="input_talos_node_image"></a> [talos\_node\_image](#input\_talos\_node\_image) | Literal Talos node image reference used to pin the image for mirror hydration. Kept in sync with talos\_version by Renovate. | `string` | `"ghcr.io/siderolabs/talos:v1.12.6"` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The talos version to deploy. Must match the node image tag (e.g. 1.12.1 for ghcr.io/siderolabs/talos:v1.12.1). | `string` | `"1.12.6"` | no |
| <a name="input_worker_config_patches"></a> [worker\_config\_patches](#input\_worker\_config\_patches) | A YAML string of worker config patches to apply. Can be an empty string or valid YAML. | `string` | `""` | no |
| <a name="input_worker_disks"></a> [worker\_disks](#input\_worker\_disks) | Pool-level disks; used when a worker node has no disks key. Per-node disks override. | `list(any)` | `[]` | no |
| <a name="input_worker_volumes"></a> [worker\_volumes](#input\_worker\_volumes) | Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present). | `list(string)` | `[]` | no |
| <a name="input_workers"></a> [workers](#input\_workers) | A list of machine configuration details | <pre>list(object({<br/>    endpoint = string<br/>    node     = string<br/>    disks    = optional(list(any), [])<br/>    disk_selector = optional(object({<br/>      busPath  = optional(string)<br/>      modalias = optional(string)<br/>      model    = optional(string)<br/>      name     = optional(string)<br/>      serial   = optional(string)<br/>      size     = optional(string)<br/>      type     = optional(string)<br/>      uuid     = optional(string)<br/>      wwid     = optional(string)<br/>    }))<br/>    wipe_disk         = optional(bool, true)<br/>    extra_kernel_args = optional(list(string), [])<br/>    config_patches    = optional(string, "")<br/>  }))</pre> | `[]` | no |

### Outputs

No outputs.
<!-- END_TF_DOCS -->
