---
title: cluster/talos/extensions
description: Resolves Talos Image Factory extensions and triggers in-place node upgrades to the resulting installer image.
---

# cluster/talos/extensions

Adds Talos system extensions to running cluster nodes. Many CSI drivers
need kernel modules or tools that aren't in the stock Talos image
(currently the only built-in case: Longhorn needs `siderolabs/iscsi-tools`
and `siderolabs/util-linux-tools`). This module asks the
[Talos Image Factory](https://factory.talos.dev/) for an installer image
that includes the requested extensions, then runs in-place upgrades on
every controlplane and worker via the `windsor upgrade node` CLI command.

The module is a no-op when `extensions` is empty: no schematic is built
and no upgrade fires. When the schematic ID changes (the extension list
or the Talos version changed) or a node's IP changes, the upgrade
triggers re-run for the affected nodes only.

## Wiring

Wired by [option-storage.yaml](../../../../contexts/_template/facets/option-storage.yaml)
when `cluster.storage.driver: longhorn`. No other facet currently
triggers it; storage is the only consumer of Talos extensions in this
blueprint today.

```yaml
terraform:
  - name: cluster-extensions
    path: cluster/talos/extensions
    dependsOn:
      - cluster
      - cni                 # only when cluster.cni.driver is cilium
    parallelism: 1
    inputs:
      talos_version: 1.12.6
      controlplanes:
        - hostname: controlplane-1
          endpoint: 10.5.0.10:50000
          node: 10.5.0.10
      workers: []
      extensions:
        - siderolabs/iscsi-tools
        - siderolabs/util-linux-tools
```

How those flow from `values.yaml`:

- `extensions` — facet-set, derived from `cluster.storage.driver`. Today, `longhorn` selects `[siderolabs/iscsi-tools, siderolabs/util-linux-tools]`; any other value yields `[]` and the module no-ops. Adding a new extension-needing driver is a one-line edit to `config-talos.yaml`'s `csi_extensions` map.
- `controlplanes` / `workers` — `cluster.controlplanes.nodes` / `cluster.workers.nodes`. Same node lists `cluster/talos` consumes; reshaped by the platform facet.
- `talos_version` — pinned in [config-talos.yaml](../../../../contexts/_template/facets/config-talos.yaml); Renovate maintains it. Not a typical user knob.

The `cluster` Terraform dep ensures the cluster is up before nodes are
upgraded. The conditional dep on `cni` (when Cilium is the CNI) exists
because both `cni/cilium` and this module write to the Talos machine
config; serializing them avoids concurrent-write races.
`parallelism: 1` serializes node upgrades within this module:
controlplanes first (one at a time), then workers (one at a time, via
`depends_on`).

The upgrade re-fires whenever the resolved schematic ID changes
(extension list or Talos version changed) or a node's IP changes. A
`talos_version` bump from Renovate causes a rolling upgrade across
every node. The upgrade itself is invoked via `local-exec` calling
`windsor upgrade node`, so the `windsor` CLI must be available on
`$PATH` wherever this module runs (local apply, CI, etc.).

## Security

The module shells out to `windsor upgrade node` with `TALOSCONFIG` and
`KUBECONFIG` pointed at `${context_path}/.talos/config` and
`${context_path}/.kube/config` (the same files [`cluster/talos`](../)
writes at mode `0600`). The schematic ID resolved against
`factory.talos.dev` is content-addressed and reproducible across
re-plans for the same extension list.

## See also

- [cluster/talos](../) — the parent module that bootstraps the cluster this one upgrades.
- [option-storage.yaml](../../../../contexts/_template/facets/option-storage.yaml) — the only current consumer (gates on `cluster.storage.driver: longhorn`).
- [config-talos.yaml](../../../../contexts/_template/facets/config-talos.yaml) — the `csi_extensions` map links storage drivers to required extensions.
- Talos Image Factory — https://factory.talos.dev/

## Reference

The full module interface — every input, output, and resource — is
listed below. Override any input from your context by adding a tfvars
file at `contexts/<context>/terraform/cluster-extensions.tfvars`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=1.8 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.11.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.2 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |

### Modules

No modules.

### Resources

| Name | Type |
|------|------|
| [null_resource.upgrade_controlplane](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.upgrade_worker](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [talos_image_factory_schematic.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/image_factory_schematic) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context_path"></a> [context\_path](#input\_context\_path) | The path to the context folder, where kubeconfig and talosconfig are stored | `string` | `""` | no |
| <a name="input_controlplanes"></a> [controlplanes](#input\_controlplanes) | List of controlplane nodes to upgrade. Only node and endpoint are required. | <pre>list(object({<br/>    node     = string<br/>    endpoint = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extensions"></a> [extensions](#input\_extensions) | Talos Image Factory extension names to install (e.g. ["siderolabs/iscsi-tools"]). | `list(string)` | `[]` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The talos version to deploy. | `string` | n/a | yes |
| <a name="input_workers"></a> [workers](#input\_workers) | List of worker nodes to upgrade. Only node and endpoint are required. | <pre>list(object({<br/>    node     = string<br/>    endpoint = string<br/>  }))</pre> | `[]` | no |

### Outputs

No outputs.
<!-- END_TF_DOCS -->