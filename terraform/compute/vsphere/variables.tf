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

variable "datacenter" {
  description = "vSphere datacenter name (exact match as shown in the vCenter inventory)"
  type        = string
}

variable "cluster" {
  description = "vSphere compute cluster name. VMs are scheduled onto hosts in this cluster"
  type        = string
}

variable "datastore" {
  description = "Datastore or datastore cluster name where VM disks are placed"
  type        = string
}

variable "network" {
  description = "Port group name the VM primary NIC attaches to (e.g. 'VM Network' or 'vlan-prod-100')"
  type        = string
}

variable "folder" {
  description = "VM folder path relative to the datacenter VM folder root. Empty string places VMs at the datacenter root"
  type        = string
  default     = ""
}

variable "resource_pool" {
  description = "Resource pool path relative to the compute cluster. Empty string uses the cluster's root resource pool"
  type        = string
  default     = ""
}

variable "allow_unverified_ssl" {
  description = "Disable TLS certificate verification for the vCenter API. Override via VSPHERE_ALLOW_UNVERIFIED_SSL env var. Only set true when the vCenter uses a cert that cannot be verified by the runner's trust store"
  type        = bool
  default     = false
}

variable "network_cidr" {
  description = "CIDR block of the network VMs attach to (e.g. 10.5.0.0/16). Used for sequential IP assignment when instances declare an ipv4 base address and for baking the static-network config into each per-node machineconfig"
  type        = string
  default     = null
}

variable "network_gateway" {
  description = "Default route gateway for static IP configuration. Delivered to each node's machineconfig via guestinfo"
  type        = string
  default     = null
}

variable "network_nameservers" {
  description = "DNS resolvers seeded into each node's machineconfig. Delivered via guestinfo alongside the static IP config"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "cluster_name" {
  description = "Talos cluster name. Baked into every per-node machineconfig; must match what cluster/talos receives"
  type        = string
  default     = "talos"
}

variable "cluster_endpoint" {
  description = "Cluster control-plane API endpoint baked into every per-node machineconfig (e.g. https://10.5.0.10:6443)"
  type        = string
  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must start with https://"
  }
}

variable "talos_version" {
  description = "Pinned Talos version (semver, no v-prefix). Used to call talos_machine_secrets and stamp machineconfig templates"
  type        = string
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version should be in semver format like '1.13.3'."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  # renovate: datasource=github-releases depName=kubernetes package=kubernetes/kubernetes
  default = "1.36.2"
}

variable "common_config_patches" {
  description = "Cluster-wide Talos machine config patch (YAML string). Applied to every node's machineconfig before guestinfo delivery"
  type        = string
  default     = ""
}

variable "images" {
  description = "Map of image references the module deploys via OVF. Each entry is deployed with ovf_deploy on first apply and ignored on subsequent applies (lifecycle.ignore_changes). Instances reference an image by its map key; when an instance's image field is empty, no OVF deploy is performed and the VM boots from a blank disk."
  type = map(object({
    url             = string
    keep_on_destroy = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.images : can(regex("^https?://", v.url))
    ])
    error_message = "images: each url must be an http or https URL"
  }
}

variable "instances" {
  description = "List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …). ipv4 is the starting address; sequential instances increment the host octet. Set image to a key in var.images to deploy from OVA; leave empty for a blank-disk VM. Talos machineconfig is delivered via guestinfo only when role is controlplane or worker."
  type = list(object({
    name           = string              # VM name prefix (becomes {name}-N when count > 1)
    count          = optional(number, 1)
    role           = optional(string)    # "controlplane", "worker", or any custom role
    image          = optional(string)    # key into var.images; empty = blank disk (no OVF deploy)
    cpu            = optional(number, 4)
    memory         = optional(number, 8)   # GiB
    root_disk_size = optional(number, 30)  # GiB
    ipv4           = optional(string)      # Base IP (bare or CIDR); sequential when count > 1
    vlan_id        = optional(number)      # Access-mode VLAN ID on the port group adapter
    notes          = optional(string)
    desired_state  = optional(string, "poweredOn")
  }))
  default = []

  validation {
    condition     = alltrue([for inst in var.instances : contains(["poweredOn", "poweredOff", "suspended"], inst.desired_state)])
    error_message = "instance.desired_state must be poweredOn, poweredOff, or suspended"
  }
}
