#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "context_id" {
  description = "The windsor context id for this deployment"
  type        = string
  default     = ""
}

variable "network_name" {
  description = "Name of the network to use. If empty, a default name will be generated. This is usually the device the network will appear as to instances"
  type        = string
  default     = ""
}

variable "create_network" {
  description = "Whether to create the network. If false, network_name must reference an existing network"
  type        = bool
  default     = true
}

variable "network_description" {
  description = "Description of the network"
  type        = string
  default     = null
}

variable "network_type" {
  description = "The type of network to create. Can be one of: bridge, macvlan, sriov, ovn, or physical. If no type is specified, a bridge network is created"
  type        = string
  default     = "bridge"
  validation {
    condition     = contains(["bridge", "macvlan", "sriov", "ovn", "physical"], var.network_type)
    error_message = "Network type must be one of: bridge, macvlan, sriov, ovn, or physical"
  }
}

variable "network_cidr" {
  description = "CIDR block for the network (e.g., '10.5.0.0/24'). Used to set the network gateway address"
  type        = string
  default     = null
}

variable "enable_dhcp" {
  description = "Enable DHCP for automatic IP assignment. Static IPs on device ipv4.address act as static DHCP leases when enabled"
  type        = bool
  default     = true
}

variable "enable_nat" {
  description = "Enable NAT for external network connectivity"
  type        = bool
  default     = true
}

variable "network_config" {
  description = "Map of key/value pairs of network config settings. See Incus networking configuration reference for all network details. DHCP and NAT can be controlled via enable_dhcp and enable_nat variables"
  type        = map(string)
  default     = null
}

variable "network_target" {
  description = "Specify a target node in a cluster for the network"
  type        = string
  default     = null
}

variable "instances" {
  description = "List of instances. Use count > 1 to create pools (instances named {name}-0, {name}-1, etc.)"
  type = list(object({
    name           = string              # Instance name (becomes prefix when count > 1)
    count          = optional(number, 1) # Number of instances. If > 1, creates pool with -0, -1 suffixes
    role           = optional(string)    # Role identifier for grouping instances (e.g., "controlplane", "worker"). If not specified, uses instance name as role.
    image          = string              # Image alias from images manifest, or direct image reference (remote ref, fingerprint, or local file)
    type           = optional(string, "container")
    description    = optional(string)
    ephemeral      = optional(bool, false)
    target         = optional(string)
    networks       = optional(list(string), [])
    network_config = optional(map(string), {})
    ipv4           = optional(string)
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    profiles = optional(list(string), [])
    devices = optional(map(object({
      type       = string
      properties = map(string)
    })), {})
    # Port forwarding from host/Colima VM to this instance
    # Format: { "name" = { "listen" = "tcp:0.0.0.0:PORT", "connect" = "tcp:INSTANCE_IP:PORT" } }
    proxy_devices = optional(map(object({
      listen  = string # e.g., "tcp:0.0.0.0:50000" (listen on Colima VM)
      connect = string # e.g., "tcp:10.5.0.87:50000" (connect to instance IP)
    })), {})
    # Enable secure boot for virtual machines (default: false)
    secureboot = optional(bool, false)
    qemu_args  = optional(string, "-boot order=c,menu=off")
    # Root disk size for virtual machines (OS disk)
    root_disk_size = optional(string, "10GB") # Size of root/OS disk (default: "10GB")
    # Additional disk devices to attach to the instance
    # Uses generic schema format: size as integer (GB), type maps to pool for Incus
    disks = optional(list(object({
      name      = string                      # Device name (e.g., "data-disk", "backup-disk")
      type      = optional(string, "default") # Disk type - maps to storage pool for Incus (e.g., "default", "gp3", "StandardSSD_LRS")
      source    = optional(string)            # File path (starts with "/") for bind mount, or storage volume name, or omit to create new volume
      size      = number                      # Volume size in GB (integer)
      path      = optional(string)            # Mount point inside instance (e.g., "/mnt/data")
      read_only = optional(bool, false)       # Mount as read-only (default: false)
    })), [])
    config = optional(map(string), {})
  }))
  default = []
  validation {
    condition     = alltrue([for instance in var.instances : contains(["container", "virtual-machine"], instance.type)])
    error_message = "Instance type must be either 'container' or 'virtual-machine'"
  }
}

variable "project" {
  description = "Name of the project where resources will be created"
  type        = string
  default     = null
}

variable "remote" {
  description = "Name of the Incus remote to use. If not set, uses provider default (usually 'local')."
  type        = string
  default     = null
}
