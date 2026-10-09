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

variable "node_name" {
  description = "Proxmox VE node that hosts the VMs (e.g. 'pve')."
  type        = string

  validation {
    condition     = var.node_name != ""
    error_message = "node_name must not be empty."
  }
}

variable "datastore_id" {
  description = "Datastore for VM disks, EFI disks, and cloud-init drives (e.g. 'local-lvm')."
  type        = string
  default     = "local-lvm"
}

variable "image_datastore_id" {
  description = "Datastore that receives downloaded images. It must allow the 'import' content type."
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Linux bridge the VM NIC attaches to (e.g. 'vmbr0')."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for the VM NIC. Null leaves the NIC untagged."
  type        = number
  default     = null

  validation {
    condition     = var.vlan_id == null || (var.vlan_id >= 1 && var.vlan_id <= 4094)
    error_message = "vlan_id must be between 1 and 4094."
  }
}

variable "network_cidr" {
  description = "CIDR of the network the VMs attach to. Supplies the prefix length for static addresses."
  type        = string
  default     = "10.5.0.0/16"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid IPv4 CIDR."
  }
}

variable "network_gateway" {
  description = "IPv4 default gateway written to static guests."
  type        = string
  default     = null
}

variable "network_nameservers" {
  description = "DNS resolvers written to guests."
  type        = list(string)
  default     = []
}

variable "arch" {
  description = "Guest architecture. arm64 selects the virt machine, OVMF firmware, and a SCSI cloud-init drive."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "arch must be 'amd64' or 'arm64'."
  }
}

variable "cpu_type" {
  description = "QEMU CPU type. Null selects x86-64-v2-AES on amd64 and host on arm64."
  type        = string
  default     = null
}

variable "bios" {
  description = "Firmware for amd64 guests: 'seabios' or 'ovmf'. ovmf adds an EFI disk. arm64 guests always use ovmf."
  type        = string
  default     = "seabios"

  validation {
    condition     = contains(["seabios", "ovmf"], var.bios)
    error_message = "bios must be 'seabios' or 'ovmf'."
  }
}

variable "agent_timeout" {
  description = "How long the provider waits for qemu-guest-agent data, such as a DHCP guest's address."
  type        = string
  default     = "15m"
}

variable "name_suffix" {
  description = "Suffix appended to every VM name so several contexts can share one node."
  type        = string
  default     = ""
}

variable "images" {
  description = "Map of disk images the node downloads into import storage, keyed by the name instances reference. Each url must point at an uncompressed qcow2, raw, or vmdk image; file_name must end in the matching extension."
  type = map(object({
    url            = string
    file_name      = string
    upload_timeout = optional(number, 1800)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.images : can(regex("^https?://", v.url))])
    error_message = "images: each url must be an http or https URL."
  }

  validation {
    condition     = alltrue([for k, v in var.images : can(regex("\\.(qcow2|raw|vmdk)$", v.file_name))])
    error_message = "images: each file_name must end in .qcow2, .raw, or .vmdk."
  }
}

variable "instances" {
  description = "List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …). ipv4 is the starting address; sequential instances increment the host octet. Omit ipv4 for DHCP so the module waits for qemu-guest-agent to report an address. Set image to a key in var.images to boot from that image; leave it empty for a blank disk."
  type = list(object({
    name           = string
    count          = optional(number, 1)
    role           = optional(string)
    image          = optional(string)
    cpu            = optional(number, 4)
    memory         = optional(number, 8)  # GiB
    root_disk_size = optional(number, 30) # GiB
    ipv4           = optional(string)
    vm_id          = optional(number)
    mac_address    = optional(string)
    notes          = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for inst in var.instances : inst.ipv4 == null || inst.count <= 1 || (
        tonumber(split(".", split("/", inst.ipv4)[0])[3]) + (inst.count - 1) <= 255
      )
    ])
    error_message = "instances: ipv4 starting octet plus (count - 1) must not exceed 255"
  }

  validation {
    condition     = alltrue([for inst in var.instances : inst.root_disk_size >= 10])
    error_message = "instances: root_disk_size must be at least 10 GiB."
  }
}
