---
title: Proxmox
description: Talos VMs on Proxmox VE.
---

VM substrate for Talos clusters on a single Proxmox VE node. The node downloads
the Talos nocloud disk image from the Image Factory into its import storage, and
each VM imports that image as its root disk. A Proxmox cloud-init drive carries
the node's static address, so Talos boots into maintenance mode at a known IP.
The `cluster/talos` module then generates the cluster identity and applies each
node's machineconfig over the Talos API. Pairs with the `cluster/talos` module.

## Credentials

The `bpg/proxmox` provider authenticates via environment variables, not Terraform
inputs. They do not appear in the Inputs table below and must be present in the
environment when running `plan`/`apply`:

| Variable | Required | Description |
|----------|:--------:|-------------|
| `PROXMOX_VE_ENDPOINT` | yes | API URL, e.g. `https://pve.example.lan:8006/` |
| `PROXMOX_VE_API_TOKEN` | yes | API token, `user@realm!tokenid=secret` |
| `PROXMOX_VE_INSECURE` | no | `true` to skip TLS verification (self-signed node certificate) |

Under the Windsor CLI, set `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_INSECURE` in the
context `environment:` block, and the token from a secret reference or the
context's `.env` file. Outside the CLI, export them directly before invoking
Terraform. The module needs no SSH access to the node.

## Host prerequisites

The module reads nothing from the node inventory beyond the names it is given.
The following must already exist:

- a node named as passed in `node_name`;
- a datastore for VM disks (`datastore_id`, default `local-lvm`). A directory
  datastore such as `local` also works once it allows the `images` content type;
- an image datastore with the `import` content type enabled (`image_datastore_id`,
  default `local`). Proxmox VE 8.4 or later supports it. Enable it with
  `pvesm set local --content iso,vztmpl,backup,import`;
- a Linux bridge for the VM NICs (`network_bridge`, default `vmbr0`), on the LAN
  that `network_cidr` describes.

The node must reach `factory.talos.dev` over HTTPS to download the image.

## API token privileges

Grant the token's user a role on `/` with these privileges. This set was verified
on Proxmox VE 9.2 with `bpg/proxmox` 0.116 through create, refresh, and destroy:

```text
Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate
Sys.Audit Sys.Modify SDN.Use
VM.Allocate VM.Audit VM.PowerMgmt VM.GuestAgent.Audit
VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory
VM.Config.Network VM.Config.Options
```

`Datastore.Allocate` deletes the downloaded image on destroy. `VM.GuestAgent.Audit`
reads the guest agent's addresses, which DHCP instances need. `Sys.Audit` and
`Sys.Modify` gate the URL metadata query that precedes each image download. For
example:

```bash
pveum role add WindsorProvisioner --privs "Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Sys.Audit,Sys.Modify,SDN.Use,VM.Allocate,VM.Audit,VM.PowerMgmt,VM.GuestAgent.Audit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options"
pveum user add windsor@pve
pveum acl modify / --users windsor@pve --roles WindsorProvisioner
pveum user token add windsor@pve terraform --privsep 0
```

## Image and boot

`images` entries must point at an uncompressed `.qcow2`, `.raw`, or `.vmdk`
image, such as the Image Factory's `nocloud-amd64.qcow2`. Use a schematic that
includes `siderolabs/qemu-guest-agent`, which reports guest addresses to Proxmox.
`disk.import_from` is read only when a VM is created, so a new image does not
replace existing VMs. Upgrade nodes with `windsor upgrade node` and the
`factory.talos.dev/nocloud-installer/<schematic>` image instead.

Instances with an `ipv4` get a static address through cloud-init. The module also
emits that address as a machineconfig patch in each `controlplanes` and `workers`
entry, so `cluster/talos` keeps it when it applies the config. Instances without an
`ipv4` take a DHCP lease, and the module waits for the guest agent to report it.

`arch = "arm64"` targets Proxmox VE on arm64 hosts with the `virt` machine, OVMF
firmware, the `host` CPU type, and a SCSI cloud-init drive. The amd64 defaults are
`q35`, SeaBIOS, `x86-64-v2-AES`, and an IDE cloud-init drive.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.116 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.116.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_download_file.images](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/download_file) | resource |
| [proxmox_virtual_environment_vm.instances](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_agent_timeout"></a> [agent\_timeout](#input\_agent\_timeout) | How long the provider waits for qemu-guest-agent data, such as a DHCP guest's address. | `string` | `"15m"` | no |
| <a name="input_arch"></a> [arch](#input\_arch) | Guest architecture. arm64 selects the virt machine, OVMF firmware, and a SCSI cloud-init drive. | `string` | `"amd64"` | no |
| <a name="input_bios"></a> [bios](#input\_bios) | Firmware for amd64 guests: 'seabios' or 'ovmf'. ovmf adds an EFI disk. arm64 guests always use ovmf. | `string` | `"seabios"` | no |
| <a name="input_context"></a> [context](#input\_context) | The windsor context id for this deployment. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. Alias for var.context. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | QEMU CPU type. Null selects x86-64-v2-AES on amd64 and host on arm64. | `string` | `null` | no |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore for VM disks, EFI disks, and cloud-init drives (e.g. 'local-lvm'). | `string` | `"local-lvm"` | no |
| <a name="input_image_datastore_id"></a> [image\_datastore\_id](#input\_image\_datastore\_id) | Datastore that receives downloaded images. It must allow the 'import' content type. | `string` | `"local"` | no |
| <a name="input_images"></a> [images](#input\_images) | Map of disk images the node downloads into import storage, keyed by the name instances reference. Each url must point at an uncompressed qcow2, raw, or vmdk image; file\_name must end in the matching extension. | <pre>map(object({<br/>    url            = string<br/>    file_name      = string<br/>    upload_timeout = optional(number, 1800)<br/>  }))</pre> | `{}` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …). ipv4 is the starting address; sequential instances increment the host octet. Omit ipv4 for DHCP so the module waits for qemu-guest-agent to report an address. Set image to a key in var.images to boot from that image; leave it empty for a blank disk. | <pre>list(object({<br/>    name           = string<br/>    count          = optional(number, 1)<br/>    role           = optional(string)<br/>    image          = optional(string)<br/>    cpu            = optional(number, 4)<br/>    memory         = optional(number, 8)  # GiB<br/>    root_disk_size = optional(number, 30) # GiB<br/>    ipv4           = optional(string)<br/>    vm_id          = optional(number)<br/>    mac_address    = optional(string)<br/>    notes          = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Suffix appended to every VM name so several contexts can share one node. | `string` | `""` | no |
| <a name="input_network_bridge"></a> [network\_bridge](#input\_network\_bridge) | Linux bridge the VM NIC attaches to (e.g. 'vmbr0'). | `string` | `"vmbr0"` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR of the network the VMs attach to. Supplies the prefix length for static addresses. | `string` | `"10.5.0.0/16"` | no |
| <a name="input_network_gateway"></a> [network\_gateway](#input\_network\_gateway) | IPv4 default gateway written to static guests. | `string` | `null` | no |
| <a name="input_network_nameservers"></a> [network\_nameservers](#input\_network\_nameservers) | DNS resolvers written to guests. | `list(string)` | `[]` | no |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Proxmox VE node that hosts the VMs (e.g. 'pve'). | `string` | n/a | yes |
| <a name="input_vlan_id"></a> [vlan\_id](#input\_vlan\_id) | VLAN tag for the VM NIC. Null leaves the NIC untagged. | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Controlplane VMs formatted for cluster/talos (hostname, endpoint, node, config\_patches). DHCP guests appear once qemu-guest-agent reports an IP |
| <a name="output_instances"></a> [instances](#output\_instances) | Flat list of all VMs. Generic shape (name, hostname, ipv4, ipv6, status, type, image, role, instance\_id) matching compute/vsphere and compute/hyperv |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Bridge the VMs are attached to |
| <a name="output_workers"></a> [workers](#output\_workers) | Worker VMs formatted for cluster/talos (hostname, endpoint, node, config\_patches). DHCP guests appear once qemu-guest-agent reports an IP |
<!-- END_TF_DOCS -->
