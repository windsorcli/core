#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name of the Incus instance"
  type        = string
}

variable "image" {
  description = "Image reference for the instance. Supports image server references (remotes), direct fingerprints, or local files. Example formats: 'images:ubuntu/22.04', 'ubuntu/22.04', 'remote:alpine/3.19', 'docker:nginx:latest', or a 64-character fingerprint hash. For OCI registries (e.g., Docker Hub or GHCR), a remote must be added first with --protocol=oci. Local files are supported by providing a tarball or directory path. The default 'images:' remote is pre-configured in Incus. Remotes must be added via 'incus remote add' before use. See Incus documentation for more details."
  type        = string
}

variable "type" {
  description = "Type of instance (container or virtual-machine)"
  type        = string
  default     = "container"
  validation {
    condition     = contains(["container", "virtual-machine"], var.type)
    error_message = "Instance type must be either 'container' or 'virtual-machine'"
  }
}

variable "description" {
  description = "Description of the instance"
  type        = string
  default     = null
}

variable "ephemeral" {
  description = "Whether the instance is ephemeral (destroyed on stop)"
  type        = bool
  default     = false
}

variable "target" {
  description = "Target cluster member for the instance"
  type        = string
  default     = null
}

variable "project" {
  description = "Name of the project where the instance will be created"
  type        = string
  default     = null
}

variable "remote" {
  description = "The remote in which the instance will be created"
  type        = string
  default     = null
}

variable "network_name" {
  description = "Name of the default network to attach the instance to"
  type        = string
}

variable "networks" {
  description = "List of network names to attach to the instance (overrides network_name)"
  type        = list(string)
  default     = []
}

variable "network_config" {
  description = "Additional network configuration properties"
  type        = map(string)
  default     = {}
}

variable "ipv4" {
  description = "Static IPv4 address for the primary network interface (e.g., '10.5.0.87' or '10.5.0.87/24'). CIDR notation is optional; prefix length is derived from network_cidr when incrementing for count > 1. If not specified, DHCP will be used"
  type        = string
  default     = null
  validation {
    condition = var.ipv4 == null || (
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$", var.ipv4)) &&
      # Validate octets are in valid range (0-255)
      alltrue([
        for octet in split(".", split("/", var.ipv4)[0]) : tonumber(octet) >= 0 && tonumber(octet) <= 255
      ])
    )
    error_message = "IPv4 address must be in format 'x.x.x.x' or 'x.x.x.x/prefix' with octets in range 0-255 (e.g., '10.5.0.87' or '10.5.0.87/24')"
  }
}

variable "ipv6" {
  description = "Static IPv6 address for the primary network interface (e.g., '2001:db8::1' or '2001:db8::1/64'). CIDR notation is optional. If not specified, IPv6 will be auto-assigned if the network supports it"
  type        = string
  default     = null
  validation {
    # Validate IPv6 format: must contain colons and hex digits, optional CIDR prefix
    # This catches common errors while being permissive enough for various IPv6 formats
    condition     = var.ipv6 == null || (can(regex(":", var.ipv6)) && can(regex("^[0-9a-fA-F:]+(/[0-9]{1,3})?$", var.ipv6)))
    error_message = "IPv6 address must be in valid IPv6 format with colons and hex digits (e.g., '2001:db8::1' or '2001:db8::1/64')"
  }
}

variable "wait_for_ipv4" {
  description = "Wait for IPv4 address to be assigned on eth0. Useful for DHCP instances to ensure IPv4 is available before proceeding. Defaults to true. Set to false to disable waiting for IPv4."
  type        = bool
  default     = true
}

variable "wait_for_ipv6" {
  description = "Wait for IPv6 address to be assigned on eth0. Useful for IPv6-only or dual-stack instances. Defaults to false unless static IPv6 is configured. Set to true to wait for DHCP-assigned IPv6."
  type        = bool
  default     = null
}

variable "limits" {
  description = "Resource limits for the instance"
  type = object({
    cpu    = optional(string)
    memory = optional(string)
  })
  default = null
}

variable "profiles" {
  description = "List of profiles to apply to the instance"
  type        = list(string)
  default     = []
}

variable "devices" {
  description = "Additional devices to attach to the instance"
  type = map(object({
    type       = string
    properties = map(string)
  }))
  default = {}
}

variable "disks" {
  description = "Additional disk devices to attach to the instance. Expects Incus format: size as string (e.g., '50GB'), pool for storage pool."
  type = list(object({
    name      = string
    pool      = string           # Storage pool name
    source    = optional(string) # Optional - file path (starts with "/") or volume name, or omit to create new volume
    size      = string           # Volume size as string (e.g., "50GB")
    path      = optional(string) # Optional - mount point inside instance
    read_only = optional(bool, false)
  }))
  default = []
}

variable "proxy_devices" {
  description = "Proxy devices for port forwarding from host/Colima VM to this instance"
  type = map(object({
    listen  = string
    connect = string
  }))
  default = {}
}

variable "secureboot" {
  description = "Enable secure boot for virtual machines (default: false)"
  type        = bool
  default     = false
}

variable "root_disk_size" {
  description = "Size of the root disk for virtual machines (e.g., '20GB'). Default: '10GB'."
  type        = string
  default     = "10GB"
}

variable "qemu_args" {
  description = "QEMU command-line arguments for virtual machines (default: boot from disk, disable menu). Set to empty string to disable."
  type        = string
  default     = "-boot order=c,menu=off"
}

variable "config" {
  description = "Additional instance configuration (merged last, can override defaults)"
  type        = map(string)
  default     = {}
}

variable "ipv4_filtering_enabled" {
  description = "Enable IPv4 filtering on the network interface (prevents ARP spoofing). When true, only allows traffic from the VM's assigned IP. Set to false for LoadBalancer services (kube-vip, MetalLB) that need to respond to ARP for VIPs. Default: false (allows LoadBalancer functionality)."
  type        = bool
  default     = false
}

