---
title: compute/vsphere
description: Talos VMs on VMware vSphere.
---

# compute/vsphere

VM substrate for Talos clusters on VMware vSphere. Provisions Talos
control-plane and worker VMs from the Talos vmware OVA, delivering
per-node machineconfig via VMware GuestInfo at creation time. Generates
cluster identity (machine secrets) inline so no separate config step is
required before `cluster/talos`. Pairs with the `cluster/talos` module.

## Credentials

The vSphere provider authenticates via environment variables, not Terraform
inputs — so they do not appear in the Inputs table below and must be present in
the environment when running `plan`/`apply`:

| Variable | Required | Description |
|----------|:--------:|-------------|
| `VSPHERE_SERVER` | yes | vCenter hostname or IP |
| `VSPHERE_USER` | yes | vCenter username (e.g. `administrator@vsphere.local`) |
| `VSPHERE_PASSWORD` | yes | vCenter password |
| `VSPHERE_ALLOW_UNVERIFIED_SSL` | no | `true` to skip TLS verification (self-signed vCenter certs) |

Under the Windsor CLI these are exported automatically from the context
`vsphere` config block (`server`, `user`, `insecure`) plus a secret reference
for the password — the password is never written to config in plaintext. Outside
the CLI, export them directly before invoking Terraform.

## Inventory prerequisites

This module **reads** its vSphere inventory via data sources — it does not create
it. The following must already exist in vCenter, named exactly as passed in
`datacenter` / `cluster` / `datastore` / `network`:

- a **datacenter**;
- a **compute cluster** (a `ClusterComputeResource`) with at least one ESXi host
  joined to it — a host added directly to the datacenter (not in a cluster) does
  not satisfy the `vsphere_compute_cluster` lookup;
- a **datastore** and a **port group** reachable from that host.

The ESXi host must also have outbound access to `factory.talos.dev` so it can
pull the Talos OVA referenced in `images` at deploy time.

To create or inspect this inventory out of band, `govc` reads the same
credentials via `GOVC_URL` (`https://$VSPHERE_SERVER`), `GOVC_USERNAME`,
`GOVC_PASSWORD`, and `GOVC_INSECURE` — mirror the `VSPHERE_*` values into those.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.11.0 |
| <a name="requirement_vsphere"></a> [vsphere](#requirement\_vsphere) | ~> 2.10 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |
| <a name="provider_vsphere"></a> [vsphere](#provider\_vsphere) | 2.12.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_secrets) | resource |
| [vsphere_folder.vm](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/resources/folder) | resource |
| [vsphere_virtual_machine.instances](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/resources/virtual_machine) | resource |
| [talos_machine_configuration.controlplane](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.worker](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |
| [vsphere_compute_cluster.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/compute_cluster) | data source |
| [vsphere_datacenter.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/datacenter) | data source |
| [vsphere_datastore.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/datastore) | data source |
| [vsphere_host.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/host) | data source |
| [vsphere_network.this](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/network) | data source |
| [vsphere_resource_pool.named](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/data-sources/resource_pool) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster"></a> [cluster](#input\_cluster) | vSphere compute cluster name. VMs are scheduled onto hosts in this cluster | `string` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | Cluster control-plane API endpoint baked into every per-node machineconfig (e.g. https://192.168.0.10:6443). Required when instances include controlplane or worker roles. | `string` | `""` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Talos cluster name. Baked into every per-node machineconfig. | `string` | `"talos"` | no |
| <a name="input_common_config_patches"></a> [common\_config\_patches](#input\_common\_config\_patches) | Cluster-wide Talos machine config patch (YAML string). Applied to every node's machineconfig. | `string` | `""` | no |
| <a name="input_context"></a> [context](#input\_context) | The windsor context id for this deployment. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. Alias for var.context. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_controlplane_config_patches"></a> [controlplane\_config\_patches](#input\_controlplane\_config\_patches) | Controlplane-only Talos machine config patch (YAML string). | `string` | `""` | no |
| <a name="input_datacenter"></a> [datacenter](#input\_datacenter) | vSphere datacenter name (exact match as shown in the vCenter inventory) | `string` | n/a | yes |
| <a name="input_datastore"></a> [datastore](#input\_datastore) | Datastore or datastore cluster name where VM disks are placed | `string` | n/a | yes |
| <a name="input_folder"></a> [folder](#input\_folder) | VM folder path relative to the datacenter VM folder root. Empty string places VMs at the datacenter root | `string` | `""` | no |
| <a name="input_host_system"></a> [host\_system](#input\_host\_system) | ESXi host name or IP to place VMs on. Required by the vSphere provider for OVF deployment. Empty string auto-selects the sole host in the datacenter (single-host clusters). | `string` | `""` | no |
| <a name="input_images"></a> [images](#input\_images) | Map of image references the module deploys via OVF. Each entry is deployed with ovf\_deploy on first apply and ignored on subsequent applies (lifecycle.ignore\_changes). Instances reference an image by its map key; when an instance's image field is empty, no OVF deploy is performed and the VM boots from a blank disk. | <pre>map(object({<br/>    url             = string<br/>    keep_on_destroy = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …). ipv4 is the starting address; sequential instances increment the host octet. Set image to a key in var.images to deploy from OVA; leave empty for a blank-disk VM. GuestInfo machineconfig is generated inside this module for controlplane and worker roles. | <pre>list(object({<br/>    name           = string<br/>    count          = optional(number, 1)<br/>    role           = optional(string)<br/>    image          = optional(string)<br/>    cpu            = optional(number, 4)<br/>    memory         = optional(number, 8)  # GiB<br/>    root_disk_size = optional(number, 30) # GiB<br/>    ipv4           = optional(string)<br/>    notes          = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to install. | `string` | `"1.36.2"` | no |
| <a name="input_network"></a> [network](#input\_network) | Port group name the VM primary NIC attaches to (e.g. 'VM Network' or 'vlan-prod-100') | `string` | n/a | yes |
| <a name="input_per_node_config_patches"></a> [per\_node\_config\_patches](#input\_per\_node\_config\_patches) | Per-node Talos machineconfig patches as YAML strings, keyed by VM name. Built by the facet from network topology (static IP, gateway, nameservers). Threaded into each node's talos\_machine\_configuration config\_patches. | `map(string)` | `{}` | no |
| <a name="input_resource_pool"></a> [resource\_pool](#input\_resource\_pool) | Resource pool path relative to the compute cluster. Empty string uses the cluster's root resource pool | `string` | `""` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Pinned Talos version (semver, no v-prefix). Required when instances include controlplane or worker roles. | `string` | `""` | no |
| <a name="input_worker_config_patches"></a> [worker\_config\_patches](#input\_worker\_config\_patches) | Worker-only Talos machine config patch (YAML string). | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_client_configuration"></a> [client\_configuration](#output\_client\_configuration) | Talos client configuration (CA cert + admin cert/key). Pass to cluster/talos as var.client\_configuration. |
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Controlplane VMs formatted for cluster/talos (hostname, endpoint, node). Populated once vmtoolsd reports a guest IP to vCenter |
| <a name="output_instances"></a> [instances](#output\_instances) | Flat list of all VMs. Generic shape (name, hostname, ipv4, ipv6, status, type, image, role) matching compute/hyperv and compute/incus |
| <a name="output_machine_secrets"></a> [machine\_secrets](#output\_machine\_secrets) | Talos cluster identity. Pass to cluster/talos as var.machine\_secrets so it shares the same cluster CA. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Port group name the VMs are attached to |
| <a name="output_workers"></a> [workers](#output\_workers) | Worker VMs formatted for cluster/talos (hostname, endpoint, node). Populated once vmtoolsd reports a guest IP to vCenter |
<!-- END_TF_DOCS -->
