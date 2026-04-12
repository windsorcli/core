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

variable "controlplanes" {
  description = "List of controlplane nodes to upgrade. Only node and endpoint are required."
  type = list(object({
    node     = string
    endpoint = string
  }))
  default = []
}

variable "workers" {
  description = "List of worker nodes to upgrade. Only node and endpoint are required."
  type = list(object({
    node     = string
    endpoint = string
  }))
  default = []
}
