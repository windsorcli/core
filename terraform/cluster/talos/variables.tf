variable "context_path" {
  type        = string
  description = "The path to the context folder, where kubeconfig and talosconfig are stored"
  default     = ""
}

variable "kubernetes_version" {
  description = "The kubernetes version to deploy, with or without a leading v. The v form is the tag of the Kubernetes images."
  type        = string
  # artifact: type=image name=registry.k8s.io/kube-apiserver
  # artifact: type=image name=registry.k8s.io/kube-controller-manager
  # artifact: type=image name=registry.k8s.io/kube-scheduler
  # artifact: type=image name=ghcr.io/siderolabs/kubelet
  # artifact: type=image name=registry.k8s.io/kube-proxy
  default = "v1.37.2"
  validation {
    condition     = can(regex("^v?1\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "The Kubernetes version should be in semantic version format like '1.30.3' or 'v1.30.3'."
  }
}

variable "talos_version" {
  description = "The talos version to deploy. Must match the node image tag (e.g. 1.12.1 for ghcr.io/siderolabs/talos:v1.12.1)."
  type        = string
  # renovate: datasource=github-releases depName=talos package=siderolabs/talos
  default = "1.14.6"
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "The Talos version should be in semantic version format like '1.7.6'."
  }
}

# Pre-generated cluster identity from an upstream module.
# When BOTH are null (default — incus/metal/docker/aws/azure callers): cluster/talos
# generates secrets locally via talos_machine_secrets and applies per-node configs
# over the maintenance-mode Talos API. When BOTH are supplied (hyperv path): the
# secrets came from compute/hyperv, which also signs and wraps per-node configs
# into CIDATA seed ISOs. cluster/talos then skips
# talos_machine_configuration_apply because the configs are already on the nodes
# via CIDATA, and goes straight to talos_machine_bootstrap + health checks.
variable "machine_secrets" {
  description = "Pre-generated Talos machine_secrets (output of an upstream cluster/talos-secrets module). When null (default), cluster/talos generates its own. Must be supplied together with client_configuration."
  type        = any
  sensitive   = true
  default     = null
}

variable "skip_machine_config_apply" {
  description = "Skip talos_machine_configuration_apply because the machineconfig reached the nodes out of band (hyperv CIDATA). Null (default) infers it from machine_secrets being supplied."
  type        = bool
  default     = null
}

variable "client_configuration" {
  description = "Pre-generated Talos client_configuration (output of an upstream cluster/talos-secrets module). When null (default), cluster/talos derives it from the locally-generated talos_machine_secrets. Must be supplied together with machine_secrets."
  type        = any
  sensitive   = true
  default     = null
  validation {
    condition     = (var.machine_secrets == null) == (var.client_configuration == null)
    error_message = "machine_secrets and client_configuration must be supplied together (both null = generate locally; both set = use upstream)."
  }
}

# talos_node_image is a literal mirror pin for the Talos node image. Windsor's
# mirror scanner follows this exact docker reference so `windsor mirror`
# includes the Talos image in the air-gapped registry. Renovate's docker
# manager keeps it in sync with talos_version via the annotation below.
variable "talos_node_image" {
  description = "Literal Talos node image reference used to pin the image for mirror hydration. Kept in sync with talos_version by Renovate."
  type        = string
  # renovate: datasource=docker depName=ghcr.io/siderolabs/talos packageName=ghcr.io/siderolabs/talos
  default = "ghcr.io/siderolabs/talos:v1.12.6"
}

variable "cluster_name" {
  description = "The name of the cluster."
  type        = string
  default     = "talos"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "The cluster name must not be empty."
  }
}

variable "cluster_endpoint" {
  description = "The external controlplane API endpoint (https://host:6443). If empty, derived from first controlplane's endpoint (Talos host:port → https://host:6443)."
  type        = string
  default     = "https://localhost:6443"
  validation {
    condition     = var.cluster_endpoint == "" || can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be empty or start with 'https://'."
  }
}

variable "vip_interface" {
  description = "Talos machine.network.interfaces entry, without vip, that carries the control-plane VIP. When set, the cluster_endpoint host becomes the shared VIP and MUST be an IPv4 address no control plane uses."
  type        = any
  default     = null
  validation {
    condition     = var.vip_interface == null || can(var.vip_interface.deviceSelector) || can(var.vip_interface.interface)
    error_message = "vip_interface must set deviceSelector or interface."
  }
}

variable "controlplanes" {
  description = "A list of machine configuration details for control planes."
  type = list(object({
    endpoint = string
    node     = string
    disks = optional(list(object({
      name     = optional(string)
      size     = optional(number)
      selector = optional(string)
      device   = optional(string)
    })), [])
    disk_selector = optional(object({
      busPath  = optional(string)
      modalias = optional(string)
      model    = optional(string)
      name     = optional(string)
      serial   = optional(string)
      size     = optional(string)
      type     = optional(string)
      uuid     = optional(string)
      wwid     = optional(string)
    }))
    wipe_disk         = optional(bool, true)
    extra_kernel_args = optional(list(string), [])
    install_image     = optional(string)
    overlay = optional(object({
      name  = string
      image = string
    }))
    config_patches = optional(string, "")
    instance_id    = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for controlplane in var.controlplanes : alltrue([for doc in split("\n---\n", controlplane.config_patches) : doc == "" || can(yamldecode(doc))])])
    error_message = "Each controlplane's config_patches must be an empty string or valid YAML documents."
  }
}

variable "workers" {
  description = "A list of machine configuration details"
  type = list(object({
    endpoint = string
    node     = string
    disks = optional(list(object({
      name     = optional(string)
      size     = optional(number)
      selector = optional(string)
      device   = optional(string)
    })), [])
    disk_selector = optional(object({
      busPath  = optional(string)
      modalias = optional(string)
      model    = optional(string)
      name     = optional(string)
      serial   = optional(string)
      size     = optional(string)
      type     = optional(string)
      uuid     = optional(string)
      wwid     = optional(string)
    }))
    wipe_disk         = optional(bool, true)
    extra_kernel_args = optional(list(string), [])
    install_image     = optional(string)
    overlay = optional(object({
      name  = string
      image = string
    }))
    config_patches = optional(string, "")
    instance_id    = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for worker in var.workers : alltrue([for doc in split("\n---\n", worker.config_patches) : doc == "" || can(yamldecode(doc))])])
    error_message = "Each worker's config_patches must be an empty string or valid YAML documents."
  }
}

variable "common_config_patches" {
  description = "A YAML string of common config patches to apply. Can be an empty string, valid YAML, or several YAML documents separated by --- lines."
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition     = alltrue([for doc in split("\n---\n", var.common_config_patches) : doc == "" || can(yamldecode(doc))])
    error_message = "common_config_patches must be an empty string or valid YAML documents."
  }
}

variable "controlplane_config_patches" {
  description = "A YAML string of controlplane config patches, applied after common_config_patches and the module's own patches, so they win wherever both set the same key. Can be an empty string, valid YAML, or several YAML documents separated by --- lines."
  type        = string
  default     = ""
  validation {
    condition     = alltrue([for doc in split("\n---\n", var.controlplane_config_patches) : doc == "" || can(yamldecode(doc))])
    error_message = "controlplane_config_patches must be an empty string or valid YAML documents."
  }
}

variable "worker_config_patches" {
  description = "A YAML string of worker config patches, applied after common_config_patches and the module's own patches, so they win wherever both set the same key. Can be an empty string, valid YAML, or several YAML documents separated by --- lines."
  type        = string
  default     = ""
  validation {
    condition     = alltrue([for doc in split("\n---\n", var.worker_config_patches) : doc == "" || can(yamldecode(doc))])
    error_message = "worker_config_patches must be an empty string or valid YAML documents."
  }
}

variable "worker_volumes" {
  description = "Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present)."
  type        = list(string)
  default     = []
}

variable "controlplane_volumes" {
  description = "Raw volume strings (path or host:dest). Talos extraMounts use the path (part after ':' if present)."
  type        = list(string)
  default     = []
}

variable "upgrade_nodes" {
  description = "Upgrade each node in place to the installer image for talos_version when its running version differs. Set false when cluster/talos/extensions owns the upgrade."
  type        = bool
  default     = true
}

variable "powercycle_reboot" {
  description = "Use a full ACPI power-cycle reboot instead of kexec during the node upgrade."
  type        = bool
  default     = false
}

variable "upgrade_timeout" {
  description = "Timeout for each node's upgrade, as a Go duration such as 15m or 1h30m. Applies per node, including the reboot wait."
  type        = string
  default     = "15m"
  validation {
    condition     = can(regex("^([0-9]+(ms|s|m|h))+$", var.upgrade_timeout))
    error_message = "upgrade_timeout must be a duration such as 15m or 1h30m."
  }
}

variable "upgrade_offline_timeout" {
  description = "Timeout for a node to confirm it rebooted after the upgrade request, as a Go duration. Empty uses the windsor default."
  type        = string
  default     = ""
  validation {
    condition     = var.upgrade_offline_timeout == "" || can(regex("^([0-9]+(ms|s|m|h))+$", var.upgrade_offline_timeout))
    error_message = "upgrade_offline_timeout must be empty or a duration such as 3m or 10m."
  }
}
