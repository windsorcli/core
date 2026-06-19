---
title: compute/hyperv
description: Talos VMs on Hyper-V (Windows host).
---

# compute/hyperv

VM substrate for Talos clusters on Windows hosts. Provisions Talos
control-plane and worker VMs on the Hyper-V hypervisor (ships with
Windows Pro / Enterprise / Server) — full-VM isolation, not containers.
Pairs with the `cluster/talos` module.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_hyperv"></a> [hyperv](#requirement\_hyperv) | 0.3.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_hyperv"></a> [hyperv](#provider\_hyperv) | 0.3.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [hyperv_image_file.images](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/resources/image_file) | resource |
| [hyperv_nat_static_mapping.tcp](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/resources/nat_static_mapping) | resource |
| [hyperv_nat_static_mapping.udp](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/resources/nat_static_mapping) | resource |
| [hyperv_vhd.instance_root](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/resources/vhd) | resource |
| [hyperv_virtual_switch.main](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/resources/virtual_switch) | resource |
| [hyperv_vm.instances](https://registry.terraform.io/providers/windsorcli/hyperv/0.3.1/docs/resources/vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_management_os"></a> [allow\_management\_os](#input\_allow\_management\_os) | Whether the host OS can use the bound NIC alongside VMs. Applies to External and Internal switches; rejected on Private and NAT | `bool` | `true` | no |
| <a name="input_context"></a> [context](#input\_context) | The windsor context id for this deployment. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | The windsor context id for this deployment. Alias for var.context. Typically set implicitly via TF\_VAR\_context; no need to pass in facet inputs. | `string` | `""` | no |
| <a name="input_create_network"></a> [create\_network](#input\_create\_network) | Whether to create the virtual switch. If false, network\_name must reference an existing switch on the host | `bool` | `true` | no |
| <a name="input_extra_port_forwards"></a> [extra\_port\_forwards](#input\_extra\_port\_forwards) | Operator-supplied TCP additions applied on top of port\_forwards. Used by platform-hyperv to layer gateway.publish\_ports onto the always-on baseline (k8s/Talos APIs, gateway NodePorts). Overlap with port\_forwards is a validation error; pick non-conflicting bench-side ports | `map(number)` | `{}` | no |
| <a name="input_extra_udp_port_forwards"></a> [extra\_udp\_port\_forwards](#input\_extra\_udp\_port\_forwards) | Operator-supplied UDP additions; merge semantics match extra\_port\_forwards. Overlap with udp\_port\_forwards is a validation error | `map(number)` | `{}` | no |
| <a name="input_images"></a> [images](#input\_images) | Map of image references the module places on the host. Each entry uses url-mode (provider downloads; SHA-256 verified when checksum is set), local\_path-mode (streamed from the runner), or host\_path-mode (file already exists). Instances reference an image by its map key; the resulting destination\_path becomes the differencing-VHD parent. | <pre>map(object({<br/>    destination_path = string<br/>    keep_on_destroy  = optional(bool, false)<br/>    url              = optional(string)<br/>    checksum         = optional(string)<br/>    compression      = optional(string)<br/>    local_path       = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …) | <pre>list(object({<br/>    name                 = string              # VM name (becomes prefix when count > 1)<br/>    count                = optional(number, 1) # Number of VMs. >1 stamps a pool with -1, -2 suffixes<br/>    role                 = optional(string)    # Role identifier for outputs (e.g. controlplane, worker)<br/>    image                = optional(string)    # Image reference: a key into var.images, or an absolute path on the host. Used as the differencing-VHD parent. When empty, a fresh dynamic VHDX of root_disk_size is created<br/>    generation           = optional(number, 2) # 1 (BIOS) or 2 (UEFI). Forces replacement when changed<br/>    secure_boot          = optional(bool, false)<br/>    secure_boot_template = optional(string) # UEFI Secure Boot template (gen 2 only). Common: MicrosoftWindows for Windows guests, MicrosoftUEFICertificateAuthority for broader Microsoft UEFI CA, OpenSourceShieldedVM. Leave unset to inherit Hyper-V default.<br/>    cpu                  = optional(number, 2)<br/>    memory               = optional(number, 4)  # Startup memory in GiB<br/>    memory_max           = optional(number)     # When set, dynamic memory is enabled with min=memory and max=memory_max<br/>    root_disk_size       = optional(number, 30) # Root disk size in GiB; used only when image is empty (fresh dynamic VHDX)<br/>    root_disk_path       = optional(string)     # Override path for the per-instance root VHDX. Defaults to vhd_dir\\<name>.vhdx<br/>    ipv4                 = optional(string)     # Informational only on Hyper-V; surfaced in outputs. CIDR or bare IP. Sequential when count > 1<br/>    mac_address          = optional(string)     # Static MAC; leave unset for Hyper-V dynamic allocation<br/>    vlan_id              = optional(number)     # Access-mode VLAN ID<br/>    switch_name          = optional(string)     # Override the switch this VM's NIC binds to. Defaults to network_name<br/>    notes                = optional(string)<br/>    desired_state        = optional(string, "Running") # Desired power state (Off, Running)<br/>    shutdown_mode        = optional(string)            # turn_off (hard) or graceful; null preserves Hyper-V's default<br/>    # ISO mount: a key into var.images (use the resulting destination_path) or an absolute host path. Empty/null = no DVD.<br/>    dvd_iso_path  = optional(string)<br/>    boot_from_dvd = optional(bool, false) # When true and dvd_iso_path is set, gen 2 boot order leads with the DVD (install-from-ISO flow)<br/>    # Second DVD slot — cloud-init NoCloud / Windows unattend seed ISOs. Same resolution as dvd_iso_path: a key into var.images or an absolute host path. Not in boot_order — read by the guest at runtime via volume-label scan.<br/>    cidata_iso_path = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_nat_host_address"></a> [nat\_host\_address](#input\_nat\_host\_address) | IPv4 address assigned to the host vNIC, used as the gateway for VMs on the NAT subnet. Must lie inside nat\_internal\_address\_prefix. Defaults to cidrhost(prefix, 1) at the provider layer when null | `string` | `null` | no |
| <a name="input_nat_internal_address_prefix"></a> [nat\_internal\_address\_prefix](#input\_nat\_internal\_address\_prefix) | CIDR the NetNat instance routes for, e.g. 192.168.200.0/24. Required when switch\_type=NAT; rejected otherwise | `string` | `null` | no |
| <a name="input_nat_name"></a> [nat\_name](#input\_nat\_name) | Name of the NetNat instance paired with the switch. Required when switch\_type=NAT; rejected otherwise | `string` | `null` | no |
| <a name="input_net_adapter_names"></a> [net\_adapter\_names](#input\_net\_adapter\_names) | Host NIC names to bind an External switch to. Multiple entries form a NIC team. Required when switch\_type=External; ignored otherwise | `list(string)` | `[]` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR block of the network the switch participates in. Informational only; Hyper-V does not run DHCP. Used for sequential IP assignment when instances declare an IPv4 base | `string` | `null` | no |
| <a name="input_network_description"></a> [network\_description](#input\_network\_description) | Free-form description stored on the virtual switch by Hyper-V | `string` | `null` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the Hyper-V virtual switch. Defaults to windsor-{context\_id} when empty | `string` | `""` | no |
| <a name="input_port_forward_external_ip"></a> [port\_forward\_external\_ip](#input\_port\_forward\_external\_ip) | Bench-side listen IPv4 the forwards bind to. Defaults to 0.0.0.0 (any host NIC) | `string` | `"0.0.0.0"` | no |
| <a name="input_port_forward_firewall_enabled"></a> [port\_forward\_firewall\_enabled](#input\_port\_forward\_firewall\_enabled) | Whether to manage paired NetFirewallRule entries alongside each static mapping | `bool` | `true` | no |
| <a name="input_port_forward_name_prefix"></a> [port\_forward\_name\_prefix](#input\_port\_forward\_name\_prefix) | Prefix for derived firewall rule DisplayNames. Final name is <prefix>-<protocol>-<external\_port> | `string` | `"windsor-pf"` | no |
| <a name="input_port_forward_target_ip"></a> [port\_forward\_target\_ip](#input\_port\_forward\_target\_ip) | Internal IPv4 address the port forwards target by default. Required when any *\_port\_forwards input is non-empty. Typically the controlplane VM's IP on the NAT subnet. Per-port overrides go through port\_forward\_target\_overrides | `string` | `null` | no |
| <a name="input_port_forward_target_overrides"></a> [port\_forward\_target\_overrides](#input\_port\_forward\_target\_overrides) | Per-external-port target IPv4 override, keyed by external\_port (the same key used in port\_forwards / udp\_port\_forwards). When a port appears here, its rule lands at this IP instead of var.port\_forward\_target\_ip; ports not listed fall through to the default. Use to point per-node Talos API forwards (bench:50000+i) at distinct VM IPs without overriding the gateway / NodePort baseline | `map(string)` | `{}` | no |
| <a name="input_port_forwards"></a> [port\_forwards](#input\_port\_forwards) | Map of bench-side TCP listen port to internal (in-VM) port. Requires switch\_type=NAT. Merged with extra\_port\_forwards (extra\_port\_forwards wins on collision) | `map(number)` | `{}` | no |
| <a name="input_switch_type"></a> [switch\_type](#input\_switch\_type) | Hyper-V switch type. External binds to a host NIC, Internal exposes the host plus VMs, Private is VM-VM only, NAT pairs an Internal switch with a NetNat instance for outbound NAT and inbound port forwarding | `string` | `"Internal"` | no |
| <a name="input_udp_port_forwards"></a> [udp\_port\_forwards](#input\_udp\_port\_forwards) | UDP equivalent of port\_forwards. A host port can be doubled up across protocols (e.g. DNS on tcp+udp 53) | `map(number)` | `{}` | no |
| <a name="input_vhd_dir"></a> [vhd\_dir](#input\_vhd\_dir) | Default directory on the host where per-instance VHDXs are placed (e.g. C:\\hyperv\\vhds). Each instance gets <vhd\_dir>\\<name>.vhdx unless root\_disk\_path is set explicitly | `string` | `"C:\\hyperv\\vhds"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_controlplanes"></a> [controlplanes](#output\_controlplanes) | Controlplane VMs formatted for cluster/talos (hostname, endpoint, node). Empty list until the guest reports an IP via Hyper-V integration services |
| <a name="output_instances"></a> [instances](#output\_instances) | Flat list of all VMs. Generic shape (name, hostname, ipv4, ipv6, status, type, image, role) matching compute/incus and compute/docker |
| <a name="output_network_managed"></a> [network\_managed](#output\_network\_managed) | True when the virtual switch was created by this module |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the virtual switch the VMs attach to |
| <a name="output_network_type"></a> [network\_type](#output\_network\_type) | Hyper-V switch type (External, Internal, Private). Null when create\_network is false |
| <a name="output_tcp_port_forwards"></a> [tcp\_port\_forwards](#output\_tcp\_port\_forwards) | Map of installed TCP NAT port forwards keyed by bench-side external\_port. Empty when no port\_forwards are configured (e.g. non-NAT switch types) |
| <a name="output_udp_port_forwards"></a> [udp\_port\_forwards](#output\_udp\_port\_forwards) | Map of installed UDP NAT port forwards keyed by bench-side external\_port |
| <a name="output_workers"></a> [workers](#output\_workers) | Worker VMs formatted for cluster/talos (hostname, endpoint, node). Empty list until the guest reports an IP via Hyper-V integration services |
<!-- END_TF_DOCS -->
