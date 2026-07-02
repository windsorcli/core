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
| [vsphere_virtual_machine.instances](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/resources/virtual_machine) | resource |
| [talos_machine_configuration.controlplane](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.worker](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/data-sources/machine_configuration) | data source |
| [vsphere_compute_cluster.this](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/data-sources/compute_cluster) | data source |
| [vsphere_datacenter.this](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/data-sources/datacenter) | data source |
| [vsphere_datastore.this](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/data-sources/datastore) | data source |
| [vsphere_network.this](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/data-sources/network) | data source |
| [vsphere_resource_pool.named](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs/data-sources/resource_pool) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster"></a> [cluster](#input\_cluster) | vSphere compute cluster name. VMs are scheduled onto hosts in this cluster | `string` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | Cluster control-plane API endpoint baked into every per-node machineconfig (e.g. https://10.5.0.10:6443) | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Talos cluster name. Baked into every per-node machineconfig; must match what cluster/talos receives | `string` | `"talos"` | no |
| <a name="input_common_config_patches"></a> [common\_config\_patches](#input\_common\_config\_patches) | Cluster-wide Talos machine config patch (YAML string). Applied to every node's machineconfig before guestinfo delivery | `string` | `""` | no |
| <a name="input_context"></a> [context](#input\_context) | The windsor context id for this deployment. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. Alias for var.context. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_datacenter"></a> [datacenter](#input\_datacenter) | vSphere datacenter name (exact match as shown in the vCenter inventory) | `string` | n/a | yes |
| <a name="input_datastore"></a> [datastore](#input\_datastore) | Datastore or datastore cluster name where VM disks are placed | `string` | n/a | yes |
| <a name="input_folder"></a> [folder](#input\_folder) | VM folder path relative to the datacenter VM folder root. Empty string places VMs at the datacenter root | `string` | `""` | no |
| <a name="input_images"></a> [images](#input\_images) | Map of image references the module deploys via OVF. Each entry is deployed with ovf\_deploy on first apply and ignored on subsequent applies (lifecycle.ignore\_changes). Instances reference an image by its map key; when an instance's image field is empty, no OVF deploy is performed and the VM boots from a blank disk. | <pre>map(object({<br/>    url             = string<br/>    keep_on_destroy = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …). ipv4 is the starting address; sequential instances increment the host octet. Set image to a key in var.images to deploy from OVA; leave empty for a blank-disk VM. Talos machineconfig is delivered via guestinfo only when role is controlplane or worker. | <pre>list(object({<br/>    name           = string # VM name prefix (becomes {name}-N when count > 1)<br/>    count          = optional(number, 1)<br/>    role           = optional(string) # "controlplane", "worker", or any custom role<br/>    image          = optional(string) # key into var.images; empty = blank disk (no OVF deploy)<br/>    cpu            = optional(number, 4)<br/>    memory         = optional(number, 8)  # GiB<br/>    root_disk_size = optional(number, 30) # GiB<br/>    ipv4           = optional(string)     # Base IP (bare or CIDR); sequential when count > 1<br/>    notes          = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version to install | `string` | `"1.36.2"` | no |
| <a name="input_network"></a> [network](#input\_network) | Port group name the VM primary NIC attaches to (e.g. 'VM Network' or 'vlan-prod-100') | `string` | n/a | yes |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR block of the network VMs attach to (e.g. 10.5.0.0/16). Used for sequential IP assignment when instances declare an ipv4 base address and for baking the static-network config into each per-node machineconfig | `string` | `null` | no |
| <a name="input_network_gateway"></a> [network\_gateway](#input\_network\_gateway) | Default route gateway for static IP configuration. Delivered to each node's machineconfig via guestinfo | `string` | `null` | no |
| <a name="input_network_nameservers"></a> [network\_nameservers](#input\_network\_nameservers) | DNS resolvers seeded into each node's machineconfig. Delivered via guestinfo alongside the static IP config | `list(string)` | <pre>[<br/>  "1.1.1.1",<br/>  "8.8.8.8"<br/>]</pre> | no |
| <a name="input_resource_pool"></a> [resource\_pool](#input\_resource\_pool) | Resource pool path relative to the compute cluster. Empty string uses the cluster's root resource pool | `string` | `""` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Pinned Talos version (semver, no v-prefix). Used to call talos\_machine\_secrets and stamp machineconfig templates | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_client_configuration"></a> [client\_configuration](#output\_client\_configuration) | Talos client configuration (CA cert + admin cert/key). Pass to cluster/talos as var.client\_configuration so its talos\_client\_configuration data source can generate a working talosconfig file |
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Controlplane VMs formatted for cluster/talos (hostname, endpoint, node). Populated once vmtoolsd reports a guest IP to vCenter |
| <a name="output_instances"></a> [instances](#output\_instances) | Flat list of all VMs. Generic shape (name, hostname, ipv4, ipv6, status, type, image, role) matching compute/hyperv and compute/incus |
| <a name="output_machine_secrets"></a> [machine\_secrets](#output\_machine\_secrets) | Talos cluster identity (CA, etcd CA, k8s CA, bootstrap token). Pass to cluster/talos as var.machine\_secrets so it shares the same cluster CA — cluster/talos then skips talos\_machine\_configuration\_apply (already delivered via guestinfo) and runs straight to bootstrap + kubeconfig + health checks |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Port group name the VMs are attached to |
| <a name="output_workers"></a> [workers](#output\_workers) | Worker VMs formatted for cluster/talos (hostname, endpoint, node). Populated once vmtoolsd reports a guest IP to vCenter |
<!-- END_TF_DOCS -->
