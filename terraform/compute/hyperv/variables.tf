# -----------------------------------------------------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------------------------------------------------

variable "context" {
  description = "The windsor context id for this deployment. Typically set implicitly via TF_VAR_context; no need to pass in facet inputs."
  type        = string
  default     = ""
}

variable "context_id" {
  description = "The windsor context id for this deployment. Alias for var.context. Typically set implicitly via TF_VAR_context; no need to pass in facet inputs."
  type        = string
  default     = ""
}

variable "network_name" {
  description = "Name of the Hyper-V virtual switch. Defaults to windsor-{context_id} when empty"
  type        = string
  default     = ""
}

variable "create_network" {
  description = "Whether to create the virtual switch. If false, network_name must reference an existing switch on the host"
  type        = bool
  default     = true
}

variable "switch_type" {
  description = "Hyper-V switch type. External binds to a host NIC, Internal exposes the host plus VMs, Private is VM-VM only, NAT pairs an Internal switch with a NetNat instance for outbound NAT and inbound port forwarding"
  type        = string
  default     = "Internal"

  validation {
    condition     = contains(["External", "Internal", "Private", "NAT"], var.switch_type)
    error_message = "switch_type must be one of: External, Internal, Private, NAT"
  }
}

variable "net_adapter_names" {
  description = "Host NIC names to bind an External switch to. Multiple entries form a NIC team. Required when switch_type=External; ignored otherwise"
  type        = list(string)
  default     = []
}

variable "allow_management_os" {
  description = "Whether the host OS can use the bound NIC alongside VMs. Applies to External and Internal switches; rejected on Private and NAT"
  type        = bool
  default     = true
}

variable "nat_name" {
  description = "Name of the NetNat instance paired with the switch. Required when switch_type=NAT; rejected otherwise"
  type        = string
  default     = null
}

variable "nat_internal_address_prefix" {
  description = "CIDR the NetNat instance routes for, e.g. 192.168.200.0/24. Required when switch_type=NAT; rejected otherwise"
  type        = string
  default     = null
}

variable "nat_host_address" {
  description = "IPv4 address assigned to the host vNIC, used as the gateway for VMs on the NAT subnet. Must lie inside nat_internal_address_prefix. Defaults to cidrhost(prefix, 1) at the provider layer when null"
  type        = string
  default     = null
}

variable "port_forwards" {
  description = "Map of bench-side TCP listen port to internal (in-VM) port. Requires switch_type=NAT. Merged with extra_port_forwards (extra_port_forwards wins on collision)"
  type        = map(number)
  default     = {}
}

variable "extra_port_forwards" {
  description = "Operator-supplied TCP additions applied on top of port_forwards. Used by platform-hyperv to layer gateway.publish_ports onto the always-on baseline (k8s/Talos APIs, gateway NodePorts). Overlap with port_forwards is a validation error; pick non-conflicting bench-side ports"
  type        = map(number)
  default     = {}

  validation {
    condition     = length(setintersection(keys(var.extra_port_forwards), keys(var.port_forwards))) == 0
    error_message = "extra_port_forwards must not reuse external ports already in port_forwards. The platform-hyperv facet builds the baseline (k8s/Talos APIs, gateway NodePorts) -- pick non-conflicting bench-side ports for gateway.publish_ports. Conflicting keys: ${join(", ", setintersection(keys(var.extra_port_forwards), keys(var.port_forwards)))}"
  }
}

variable "udp_port_forwards" {
  description = "UDP equivalent of port_forwards. A host port can be doubled up across protocols (e.g. DNS on tcp+udp 53)"
  type        = map(number)
  default     = {}
}

variable "extra_udp_port_forwards" {
  description = "Operator-supplied UDP additions; merge semantics match extra_port_forwards. Overlap with udp_port_forwards is a validation error"
  type        = map(number)
  default     = {}

  validation {
    condition     = length(setintersection(keys(var.extra_udp_port_forwards), keys(var.udp_port_forwards))) == 0
    error_message = "extra_udp_port_forwards must not reuse external ports already in udp_port_forwards. Conflicting keys: ${join(", ", setintersection(keys(var.extra_udp_port_forwards), keys(var.udp_port_forwards)))}"
  }
}

variable "port_forward_target_ip" {
  description = "Internal IPv4 address the port forwards target by default. Required when any *_port_forwards input is non-empty. Typically the controlplane VM's IP on the NAT subnet. Per-port overrides go through port_forward_target_overrides"
  type        = string
  default     = null
}

variable "port_forward_target_overrides" {
  description = "Per-external-port target IPv4 override, keyed by external_port (the same key used in port_forwards / udp_port_forwards). When a port appears here, its rule lands at this IP instead of var.port_forward_target_ip; ports not listed fall through to the default. Use to point per-node Talos API forwards (bench:50000+i) at distinct VM IPs without overriding the gateway / NodePort baseline"
  type        = map(string)
  default     = {}
}

variable "port_forward_external_ip" {
  description = "Bench-side listen IPv4 the forwards bind to. Defaults to 0.0.0.0 (any host NIC)"
  type        = string
  default     = "0.0.0.0"
}

variable "port_forward_name_prefix" {
  description = "Prefix for derived firewall rule DisplayNames. Final name is <prefix>-<protocol>-<external_port>"
  type        = string
  default     = "windsor-pf"
}

variable "port_forward_firewall_enabled" {
  description = "Whether to manage paired NetFirewallRule entries alongside each static mapping"
  type        = bool
  default     = true
}

variable "network_description" {
  description = "Free-form description stored on the virtual switch by Hyper-V"
  type        = string
  default     = null
}

variable "network_cidr" {
  description = "CIDR block of the network the switch participates in. Informational only; Hyper-V does not run DHCP. Used for sequential IP assignment when instances declare an IPv4 base"
  type        = string
  default     = null
}

variable "vhd_dir" {
  description = "Default directory on the host where per-instance VHDXs are placed (e.g. C:\\\\hyperv\\\\vhds). Each instance gets <vhd_dir>\\\\<name>.vhdx unless root_disk_path is set explicitly"
  type        = string
  default     = "C:\\hyperv\\vhds"
}

variable "images" {
  description = "Map of image references the module places on the host. Each entry uses url-mode (provider downloads; SHA-256 verified when checksum is set), local_path-mode (streamed from the runner), or host_path-mode (file already exists). Instances reference an image by its map key; the resulting destination_path becomes the differencing-VHD parent."
  type = map(object({
    destination_path = string
    keep_on_destroy  = optional(bool, false)
    url              = optional(string)
    checksum         = optional(string)
    compression      = optional(string)
    local_path       = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.images : !(v.url != null && v.local_path != null)
    ])
    error_message = "images: url and local_path are mutually exclusive within a single image entry"
  }

  validation {
    condition = alltrue([
      for k, v in var.images : v.compression == null || contains(["gz", "gzip", "xz", "zst", "zstd", "bz2", "bzip2"], v.compression)
    ])
    error_message = "images: compression must be one of gz, gzip, xz, zst, zstd, bz2, bzip2"
  }
}

variable "instances" {
  description = "List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …)"
  type = list(object({
    name                 = string              # VM name (becomes prefix when count > 1)
    count                = optional(number, 1) # Number of VMs. >1 stamps a pool with -1, -2 suffixes
    role                 = optional(string)    # Role identifier for outputs (e.g. controlplane, worker)
    image                = optional(string)    # Image reference: a key into var.images, or an absolute path on the host. Used as the differencing-VHD parent. When empty, a fresh dynamic VHDX of root_disk_size is created
    generation           = optional(number, 2) # 1 (BIOS) or 2 (UEFI). Forces replacement when changed
    secure_boot          = optional(bool, false)
    secure_boot_template = optional(string) # UEFI Secure Boot template (gen 2 only). Common: MicrosoftWindows for Windows guests, MicrosoftUEFICertificateAuthority for broader Microsoft UEFI CA, OpenSourceShieldedVM. Leave unset to inherit Hyper-V default.
    cpu                  = optional(number, 2)
    memory               = optional(number, 4)  # Startup memory in GiB
    memory_max           = optional(number)     # When set, dynamic memory is enabled with min=memory and max=memory_max
    root_disk_size       = optional(number, 30) # Root disk size in GiB; used only when image is empty (fresh dynamic VHDX)
    root_disk_path       = optional(string)     # Override path for the per-instance root VHDX. Defaults to vhd_dir\\<name>.vhdx
    ipv4                 = optional(string)     # Informational only on Hyper-V; surfaced in outputs. CIDR or bare IP. Sequential when count > 1
    mac_address          = optional(string)     # Static MAC; leave unset for Hyper-V dynamic allocation
    vlan_id              = optional(number)     # Access-mode VLAN ID
    switch_name          = optional(string)     # Override the switch this VM's NIC binds to. Defaults to network_name
    notes                = optional(string)
    desired_state        = optional(string, "Running") # Desired power state (Off, Running)
    shutdown_mode        = optional(string)            # turn_off (hard) or graceful; null preserves Hyper-V's default
    # ISO mount: a key into var.images (use the resulting destination_path) or an absolute host path. Empty/null = no DVD.
    dvd_iso_path  = optional(string)
    boot_from_dvd = optional(bool, false) # When true and dvd_iso_path is set, gen 2 boot order leads with the DVD (install-from-ISO flow)
    # Second DVD slot — cloud-init NoCloud / Windows unattend seed ISOs. Populated
    # automatically by this module via var.cluster_name/talos_version/cluster_endpoint
    # inputs when destination_dir is set; not passed directly.
    # Not in boot_order — read by the guest at runtime via volume-label scan.
  }))
  default = []

  validation {
    condition     = alltrue([for inst in var.instances : contains([1, 2], inst.generation)])
    error_message = "instance.generation must be 1 or 2"
  }

  validation {
    condition     = alltrue([for inst in var.instances : contains(["Off", "Running"], inst.desired_state)])
    error_message = "instance.desired_state must be Off or Running"
  }
}

variable "destination_dir" {
  description = "Directory on the Hyper-V host where per-node CIDATA seed ISOs are staged (e.g. C:\\hyperv\\images). When empty, no CIDATA ISOs are created. Must match what cluster/talos/config previously received as destination_dir."
  type        = string
  default     = ""
}

variable "network_gateway" {
  description = "Default route gateway written into each node's CIDATA network-config (cloud-init v2 gateway4 field). Required when destination_dir is non-empty."
  type        = string
  default     = null
}

variable "network_nameservers" {
  description = "DNS resolvers written into each node's CIDATA network-config (cloud-init v2 nameservers.addresses list)."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "network_interface" {
  description = "NIC name glob for the CIDATA network-config match.name field (cloud-init v2). Default e* matches both eth0 and enX0 — covers Hyper-V synthetic NICs across kernel versions."
  type        = string
  default     = "e*"
}

variable "cluster_name" {
  description = "Talos cluster name. Baked into every per-node machineconfig."
  type        = string
  default     = "talos"
}

variable "cluster_endpoint" {
  description = "Cluster control-plane API endpoint baked into every per-node machineconfig (e.g. https://192.168.0.10:6443). Required when instances include controlplane or worker roles."
  type        = string
  default     = ""
  validation {
    condition     = var.cluster_endpoint == "" || can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must start with https://"
  }
}

variable "talos_version" {
  description = "Pinned Talos version (semver, no v-prefix). Required when instances include controlplane or worker roles."
  type        = string
  default     = ""
  validation {
    condition     = var.talos_version == "" || can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version should be in semver format like '1.12.6'."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install."
  type        = string
  # renovate: datasource=github-releases depName=kubernetes package=kubernetes/kubernetes
  default = "1.36.2"
}

variable "common_config_patches" {
  description = "Cluster-wide Talos machine config patch (YAML string). Applied to every node's machineconfig."
  type        = string
  default     = ""
}

variable "controlplane_config_patches" {
  description = "Controlplane-only Talos machine config patch (YAML string)."
  type        = string
  default     = ""
}

variable "worker_config_patches" {
  description = "Worker-only Talos machine config patch (YAML string)."
  type        = string
  default     = ""
}
