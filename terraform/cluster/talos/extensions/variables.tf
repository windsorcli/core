variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig and talosconfig are stored"
  default     = ""
}

variable "talos_version" {
  description = "The talos version to deploy."
  type        = string
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "The Talos version should be in semantic version format like '1.7.6'."
  }
}

variable "extensions" {
  description = "Talos Image Factory extension names to install (e.g. [\"siderolabs/iscsi-tools\"])."
  type        = list(string)
  default     = []
}

variable "base_extensions" {
  description = "Talos Image Factory extension names the schematic always holds. They do not trigger an upgrade on their own."
  type        = list(string)
  default     = []
}

variable "installer" {
  description = "Talos Image Factory installer image name for nodes without an overlay or install_image."
  type        = string
  default     = "installer"
  validation {
    condition     = contains(["installer", "nocloud-installer"], var.installer)
    error_message = "The installer must be installer or nocloud-installer."
  }
}

variable "controlplanes" {
  description = "List of controlplane nodes to upgrade. Only node is required. A node's overlay adds its board overlay to the extensions schematic. A node's install_image replaces the extensions installer and MUST carry the extensions."
  type = list(object({
    node          = string
    endpoint      = optional(string)
    install_image = optional(string)
    overlay = optional(object({
      name  = string
      image = string
    }))
  }))
  default = []
}

variable "workers" {
  description = "List of worker nodes to upgrade. Only node is required. A node's overlay adds its board overlay to the extensions schematic. A node's install_image replaces the extensions installer and MUST carry the extensions."
  type = list(object({
    node          = string
    endpoint      = optional(string)
    install_image = optional(string)
    overlay = optional(object({
      name  = string
      image = string
    }))
  }))
  default = []
}

variable "powercycle_reboot" {
  description = "Use a full ACPI power-cycle reboot instead of the default kexec. Needed on platforms where kexec doesn't reliably register as an offline transition (e.g. nested virtualization)."
  type        = bool
  default     = false
}
