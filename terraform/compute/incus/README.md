---
title: Incus
description: Talos VMs on Incus.
---

VM substrate for Talos clusters on Incus (LXD's fork). Provisions Talos
VMs as full-VM instances on an Incus daemon or cluster. Pick this over
`compute/docker` when you need full-VM isolation or kernel features
Docker-on-Mac can't expose (e.g. nested KVM, real iSCSI). Pairs with the
`cluster/talos` module.

## Context id

Each name below has a rule narrower than the 63-character DNS label a `context_id` can be. When the id is longer than the limit shown, the module truncates the id and appends the first 6 hex characters of its SHA-256 hash. An id within the limit keeps the name unchanged. The first row is the narrowest rule.

| Name | Rule | Longest id kept |
| --- | --- | --- |
| Bridge network `net-<id>` | 15 characters, the Linux interface name limit | 11 |

## Clusters

`remote` names an Incus client remote, such as a cluster added with `incus remote add`. Each instance's `target` names the cluster member that hosts it. On a cluster, instances without a `target` go round-robin across the members, sorted by name, in the order of `instances`. On a single server, they have no `target`. An instance and its data volumes keep the member they were created on: a later `target` change has no effect, and `incus move` moves an instance.

The `platform-incus` facet sets these from `incus.remote` and `incus.targets`. Control plane N and worker N take entry (N - 1) of `incus.targets`, modulo its length. A node's `placement` in `cluster.controlplanes.nodes` or `cluster.workers.nodes` overrides the round-robin entry.

A data disk's volume is created on the same member as its instance, because a volume on a local pool belongs to one member. `default_storage_pool` names the existing pool that root disks and data disks use when they name the pool `default`. On IncusOS that pool is `local`. The facet sets it from `incus.storage_pool`.

## LAN networks

With `create_network = false`, the instances attach to the existing network in `network_name`. On a cluster, that network MUST exist on every member that hosts an instance.

With `attach_to_bridge = true`, each NIC is a bridged NIC on the host bridge that `network_name` names, such as a bridge that IncusOS creates for an interface with the `instances` role. That bridge MUST exist under the same name on every member that hosts an instance.

Incus serves DHCP only on a bridge it manages. On a macvlan network, or a bridge to the LAN, the LAN's DHCP server assigns addresses and Incus can't report them for a Talos guest. Set `static_dhcp_leases = false` and `wait_for_ipv4 = false` on each instance there. The module then leaves `ipv4` and `ipv6` off the NIC and reports them only in the outputs. Reserve each address on the LAN's DHCP server against the MAC set in `network_config.hwaddr`.

The facet does this when `incus.network` is set. Each node then declares its address, and optionally its `mac_address`, in `cluster.controlplanes.nodes` or `cluster.workers.nodes`.

## Static addresses through cloud-init

With `cloud_init_network = true`, each virtual machine with an `ipv4` gets a cloud-init network-config (version 2) in `cloud-init.network-config`. It gives `eth0` that address, `network_gateway`, and `network_nameservers`. The prefix length comes from `ipv4`, or from `network_cidr` when `ipv4` has none. Incus serves the network-config on a `cloud-init:config` disk with the volume label `cidata`, so the guest needs no agent and no DHCP reservation.

The guest MUST read nocloud data from that disk. Talos does so only on its nocloud image, such as `windsor:talos/v1.14.6/amd64/nocloud`, which names its first NIC `eth0`. The Talos metal image ignores it.

The facet sets `cloud_init_network` and boots the nocloud image when `incus.network` is set. The gateway comes from `network.gateway`, else the first host of `network.cidr_block`. The resolvers come from `network.nameservers`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_incus"></a> [incus](#requirement\_incus) | 1.2.1 |
| <a name="requirement_null"></a> [null](#requirement\_null) | 3.3.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_incus"></a> [incus](#provider\_incus) | 1.2.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_instances"></a> [instances](#module\_instances) | ./modules/instance | n/a |

## Resources

| Name | Type |
|------|------|
| [incus_image.local](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/image) | resource |
| [incus_network.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/network) | resource |
| [incus_storage_pool.pools](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/storage_pool) | resource |
| [incus_storage_volume.disks](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/resources/storage_volume) | resource |
| [terraform_data.ip_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [incus_cluster.main](https://registry.terraform.io/providers/lxc/incus/1.2.1/docs/data-sources/cluster) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attach_to_bridge"></a> [attach\_to\_bridge](#input\_attach\_to\_bridge) | Attach instance NICs to the existing host bridge named network\_name, instead of to a managed Incus network. | `bool` | `false` | no |
| <a name="input_cloud_init_network"></a> [cloud\_init\_network](#input\_cloud\_init\_network) | Give each virtual machine with an ipv4 a cloud-init network-config for eth0 with that address, network\_gateway, and network\_nameservers, on a cloud-init config drive. | `bool` | `false` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment | `string` | `""` | no |
| <a name="input_create_network"></a> [create\_network](#input\_create\_network) | Whether to create the network. If false, network\_name must reference an existing network | `bool` | `true` | no |
| <a name="input_default_storage_pool"></a> [default\_storage\_pool](#input\_default\_storage\_pool) | Existing storage pool that root disks and data disks use when they name the pool "default". IncusOS names its pool "local" | `string` | `"default"` | no |
| <a name="input_enable_dhcp"></a> [enable\_dhcp](#input\_enable\_dhcp) | Enable DHCP for automatic IP assignment. Static IPs on device ipv4.address act as static DHCP leases when enabled | `bool` | `true` | no |
| <a name="input_enable_nat"></a> [enable\_nat](#input\_enable\_nat) | Enable NAT for external network connectivity | `bool` | `true` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | List of instances. Use count > 1 to create pools (instances named {name}-0, {name}-1, etc.) | <pre>list(object({<br/>    name           = string              # Instance name (becomes prefix when count > 1)<br/>    count          = optional(number, 1) # Number of instances. If > 1, creates pool with -0, -1 suffixes<br/>    role           = optional(string)    # Role identifier for grouping instances (e.g., "controlplane", "worker"). If not specified, uses instance name as role.<br/>    image          = string              # Image alias from images manifest, or direct image reference (remote ref, fingerprint, or local file)<br/>    type           = optional(string, "container")<br/>    description    = optional(string)<br/>    ephemeral      = optional(bool, false)<br/>    target         = optional(string)<br/>    networks       = optional(list(string), [])<br/>    network_config = optional(map(string), {})<br/>    ipv4           = optional(string)<br/>    ipv6           = optional(string)<br/>    wait_for_ipv4  = optional(bool, true)<br/>    wait_for_ipv6  = optional(bool)<br/>    limits = optional(object({<br/>      cpu    = optional(string)<br/>      memory = optional(string)<br/>    }))<br/>    profiles = optional(list(string), [])<br/>    devices = optional(map(object({<br/>      type       = string<br/>      properties = map(string)<br/>    })), {})<br/>    # Port forwarding from host/Colima VM to this instance<br/>    # Format: { "name" = { "listen" = "tcp:0.0.0.0:PORT", "connect" = "tcp:INSTANCE_IP:PORT" } }<br/>    proxy_devices = optional(map(object({<br/>      listen  = string # e.g., "tcp:0.0.0.0:50000" (listen on Colima VM)<br/>      connect = string # e.g., "tcp:10.5.0.87:50000" (connect to instance IP)<br/>    })), {})<br/>    # Enable secure boot for virtual machines (default: false)<br/>    secureboot = optional(bool, false)<br/>    qemu_args  = optional(string, "-boot order=c,menu=off")<br/>    # Root disk size for virtual machines (OS disk)<br/>    root_disk_size = optional(string, "10GB") # Size of root/OS disk (default: "10GB")<br/>    # Storage pool for root disk. Must exist in storage_pools or be "default" (assumed to exist)<br/>    storage_pool = optional(string, "default")<br/>    # Additional disk devices to attach to the instance<br/>    # Uses generic schema format: size as integer (GB), type maps to pool for Incus<br/>    disks = optional(list(object({<br/>      name      = string                      # Device name (e.g., "data-disk", "backup-disk")<br/>      type      = optional(string, "default") # Disk type - maps to storage pool for Incus. Must exist in storage_pools or be "default"<br/>      source    = optional(string)            # File path (starts with "/") for bind mount, or storage volume name, or omit to create new volume<br/>      size      = number                      # Volume size in GB (integer)<br/>      path      = optional(string)            # Mount point inside instance (e.g., "/mnt/data")<br/>      read_only = optional(bool, false)       # Mount as read-only (default: false)<br/>    })), [])<br/>    config                 = optional(map(string), {})<br/>    ipv4_filtering_enabled = optional(bool, false) # Enable IPv4 filtering (prevents ARP spoofing, blocks LoadBalancer VIPs)<br/>  }))</pre> | `[]` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR block for the network (e.g., '10.5.0.0/24'). Used to set the network gateway address | `string` | `null` | no |
| <a name="input_network_config"></a> [network\_config](#input\_network\_config) | Map of key/value pairs of network config settings. See Incus networking configuration reference for all network details. DHCP and NAT can be controlled via enable\_dhcp and enable\_nat variables | `map(string)` | `null` | no |
| <a name="input_network_description"></a> [network\_description](#input\_network\_description) | Description of the network | `string` | `null` | no |
| <a name="input_network_gateway"></a> [network\_gateway](#input\_network\_gateway) | IPv4 default gateway written to cloud-init network-config. | `string` | `null` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the network to use. If empty, a default name will be generated. This is usually the device the network will appear as to instances | `string` | `""` | no |
| <a name="input_network_nameservers"></a> [network\_nameservers](#input\_network\_nameservers) | DNS resolvers written to cloud-init network-config. | `list(string)` | `[]` | no |
| <a name="input_network_target"></a> [network\_target](#input\_network\_target) | Specify a target node in a cluster for the network | `string` | `null` | no |
| <a name="input_network_type"></a> [network\_type](#input\_network\_type) | The type of network to create. Can be one of: bridge, macvlan, sriov, ovn, or physical. If no type is specified, a bridge network is created | `string` | `"bridge"` | no |
| <a name="input_project"></a> [project](#input\_project) | Name of the project where resources will be created | `string` | `null` | no |
| <a name="input_remote"></a> [remote](#input\_remote) | Name of the Incus remote to use. If not set, uses provider default (usually 'local'). | `string` | `null` | no |
| <a name="input_static_dhcp_leases"></a> [static\_dhcp\_leases](#input\_static\_dhcp\_leases) | Whether instance ipv4 and ipv6 addresses become static DHCP leases on the NIC. Set false on a network Incus serves no DHCP on, such as macvlan or a bridge to the LAN, where the addresses only feed the outputs | `bool` | `true` | no |
| <a name="input_storage_pools"></a> [storage\_pools](#input\_storage\_pools) | Map of storage pools to create. Key is pool name, value contains driver, optional source, and config. Pools with null driver are skipped (allows conditional pool creation). The 'default' pool is assumed to exist. | <pre>map(object({<br/>    driver = optional(string)          # Storage driver: dir, zfs, btrfs, lvm, ceph. Null = skip pool creation.<br/>    source = optional(string)          # Source device/path for the pool (driver-specific)<br/>    size   = optional(string)          # Pool size (for loop-file backed pools)<br/>    config = optional(map(string), {}) # Driver-specific configuration options<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | List of controlplane instances formatted for Talos (hostname, endpoint, node). Returns empty list if no controlplane instances exist or IPs are not yet assigned. |
| <a name="output_instances"></a> [instances](#output\_instances) | Flat list of all instances. Generic format with basic instance information (name, hostname, ipv4, ipv6, status, type, image, role). No k8s-specific fields. |
| <a name="output_network_managed"></a> [network\_managed](#output\_network\_managed) | Whether or not the network is managed. Null if network was not created by this module |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The name of the network being used |
| <a name="output_network_type"></a> [network\_type](#output\_network\_type) | The type of network. Can be one of: bridge, macvlan, sriov, ovn or physical. Null if network was not created by this module |
| <a name="output_workers"></a> [workers](#output\_workers) | List of worker instances formatted for Talos (hostname, endpoint, node). Returns empty list if no worker instances exist or IPs are not yet assigned. |
<!-- END_TF_DOCS -->