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

variable "per_node_config_patches" {
  description = "Per-node Talos machineconfig patches as YAML strings, keyed by VM name. Built by the facet from network topology (static IP, gateway, nameservers). Threaded into each node's talos_machine_configuration config_patches."
  type        = map(string)
  default     = {}
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
  description = "List of VM definitions. Use count > 1 to create pools (named {name}-1, {name}-2, …). ipv4 is the starting address; sequential instances increment the host octet. Set image to a key in var.images to deploy from OVA; leave empty for a blank-disk VM. GuestInfo machineconfig is generated inside this module for controlplane and worker roles."
  type = list(object({
    name           = string
    count          = optional(number, 1)
    role           = optional(string)
    image          = optional(string)
    cpu            = optional(number, 4)
    memory         = optional(number, 8)  # GiB
    root_disk_size = optional(number, 30) # GiB
    ipv4           = optional(string)
    notes          = optional(string)
  }))
  default = []
}
