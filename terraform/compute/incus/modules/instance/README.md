<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.12 |
| <a name="requirement_incus"></a> [incus](#requirement\_incus) | ~> 1.1.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_incus"></a> [incus](#provider\_incus) | 1.1.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [incus_instance.this](https://registry.terraform.io/providers/lxc/incus/latest/docs/resources/instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_config"></a> [config](#input\_config) | Additional instance configuration (merged last, can override defaults) | `map(string)` | `{}` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the instance | `string` | `null` | no |
| <a name="input_devices"></a> [devices](#input\_devices) | Additional devices to attach to the instance | <pre>map(object({<br/>    type       = string<br/>    properties = map(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_disks"></a> [disks](#input\_disks) | Additional disk devices to attach to the instance. Expects Incus format: size as string (e.g., '50GB'), pool for storage pool. | <pre>list(object({<br/>    name      = string<br/>    pool      = string           # Storage pool name<br/>    source    = optional(string) # Optional - file path (starts with "/") or volume name, or omit to create new volume<br/>    size      = string           # Volume size as string (e.g., "50GB")<br/>    path      = optional(string) # Optional - mount point inside instance<br/>    read_only = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_ephemeral"></a> [ephemeral](#input\_ephemeral) | Whether the instance is ephemeral (destroyed on stop) | `bool` | `false` | no |
| <a name="input_image"></a> [image](#input\_image) | Image reference for the instance. Supports image server references (remotes), direct fingerprints, or local files. Example formats: 'images:ubuntu/22.04', 'ubuntu/22.04', 'remote:alpine/3.19', 'docker:nginx:latest', or a 64-character fingerprint hash. For OCI registries (e.g., Docker Hub or GHCR), a remote must be added first with --protocol=oci. Local files are supported by providing a tarball or directory path. The default 'images:' remote is pre-configured in Incus. Remotes must be added via 'incus remote add' before use. See Incus documentation for more details. | `string` | n/a | yes |
| <a name="input_ipv4"></a> [ipv4](#input\_ipv4) | Static IPv4 address for the primary network interface (e.g., '10.5.0.87' or '10.5.0.87/24'). CIDR notation is optional; prefix length is derived from network\_cidr when incrementing for count > 1. If not specified, DHCP will be used | `string` | `null` | no |
| <a name="input_ipv4_filtering_enabled"></a> [ipv4\_filtering\_enabled](#input\_ipv4\_filtering\_enabled) | Enable IPv4 filtering on the network interface (prevents ARP spoofing). When true, only allows traffic from the VM's assigned IP. Set to false for LoadBalancer services (kube-vip, MetalLB) that need to respond to ARP for VIPs. Default: false (allows LoadBalancer functionality). | `bool` | `false` | no |
| <a name="input_ipv6"></a> [ipv6](#input\_ipv6) | Static IPv6 address for the primary network interface (e.g., '2001:db8::1' or '2001:db8::1/64'). CIDR notation is optional. If not specified, IPv6 will be auto-assigned if the network supports it | `string` | `null` | no |
| <a name="input_limits"></a> [limits](#input\_limits) | Resource limits for the instance | <pre>object({<br/>    cpu    = optional(string)<br/>    memory = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Incus instance | `string` | n/a | yes |
| <a name="input_network_config"></a> [network\_config](#input\_network\_config) | Additional network configuration properties | `map(string)` | `{}` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the default network to attach the instance to | `string` | n/a | yes |
| <a name="input_networks"></a> [networks](#input\_networks) | List of network names to attach to the instance (overrides network\_name) | `list(string)` | `[]` | no |
| <a name="input_profiles"></a> [profiles](#input\_profiles) | List of profiles to apply to the instance | `list(string)` | `[]` | no |
| <a name="input_project"></a> [project](#input\_project) | Name of the project where the instance will be created | `string` | `null` | no |
| <a name="input_proxy_devices"></a> [proxy\_devices](#input\_proxy\_devices) | Proxy devices for port forwarding from host/Colima VM to this instance | <pre>map(object({<br/>    listen  = string<br/>    connect = string<br/>  }))</pre> | `{}` | no |
| <a name="input_qemu_args"></a> [qemu\_args](#input\_qemu\_args) | QEMU command-line arguments for virtual machines (default: boot from disk, disable menu). Set to empty string to disable. | `string` | `"-boot order=c,menu=off"` | no |
| <a name="input_remote"></a> [remote](#input\_remote) | The remote in which the instance will be created | `string` | `null` | no |
| <a name="input_root_disk_size"></a> [root\_disk\_size](#input\_root\_disk\_size) | Size of the root disk for virtual machines (e.g., '20GB'). Default: '10GB'. | `string` | `"10GB"` | no |
| <a name="input_secureboot"></a> [secureboot](#input\_secureboot) | Enable secure boot for virtual machines (default: false) | `bool` | `false` | no |
| <a name="input_storage_pool"></a> [storage\_pool](#input\_storage\_pool) | Storage pool to use for the root disk. Default: 'default'. | `string` | `"default"` | no |
| <a name="input_target"></a> [target](#input\_target) | Target cluster member for the instance | `string` | `null` | no |
| <a name="input_type"></a> [type](#input\_type) | Type of instance (container or virtual-machine) | `string` | `"container"` | no |
| <a name="input_wait_for_ipv4"></a> [wait\_for\_ipv4](#input\_wait\_for\_ipv4) | Wait for IPv4 address to be assigned on eth0. Useful for DHCP instances to ensure IPv4 is available before proceeding. Defaults to true. Set to false to disable waiting for IPv4. | `bool` | `true` | no |
| <a name="input_wait_for_ipv6"></a> [wait\_for\_ipv6](#input\_wait\_for\_ipv6) | Wait for IPv6 address to be assigned on eth0. Useful for IPv6-only or dual-stack instances. Defaults to false unless static IPv6 is configured. Set to true to wait for DHCP-assigned IPv6. | `bool` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_image"></a> [image](#output\_image) | The image fingerprint used for the instance |
| <a name="output_ipv4"></a> [ipv4](#output\_ipv4) | The primary IPv4 address of the instance. Falls back to input ipv4 if instance address is not yet available |
| <a name="output_ipv6"></a> [ipv6](#output\_ipv6) | The primary IPv6 address of the instance. Falls back to input ipv6 if instance address is not yet available |
| <a name="output_name"></a> [name](#output\_name) | The name of the Incus instance |
| <a name="output_status"></a> [status](#output\_status) | The status of the instance |
| <a name="output_type"></a> [type](#output\_type) | The type of the Incus instance |
<!-- END_TF_DOCS -->