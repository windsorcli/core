variable "cilium_version" {
  description = "Version of the Cilium Helm chart to install."
  type        = string
  # renovate: datasource=helm depName=cilium package=cilium helmRepo=https://helm.cilium.io
  default = "1.16.19"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cilium_version))
    error_message = "cilium_version must be in X.Y.Z format."
  }
}

variable "cluster_endpoint" {
  description = "Kubernetes API server endpoint (https://host:port). Required when kube_proxy_replacement is true so Cilium can reach the API server before eBPF service rules are active."
  type        = string
  default     = ""
  validation {
    condition     = var.cluster_endpoint == "" || can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be empty or start with 'https://'."
  }
}

variable "kube_proxy_replacement" {
  description = "Replace kube-proxy with Cilium's eBPF implementation. Requires cluster_endpoint to be set. Recommended for Talos and EKS."
  type        = bool
  default     = true
}

variable "ipam_mode" {
  description = "Cilium IPAM mode. 'kubernetes' uses node CIDR ranges (default, works for Talos and standard EKS). 'eni' uses AWS ENI-based allocation for EKS native networking."
  type        = string
  default     = "kubernetes"
  validation {
    condition     = contains(["kubernetes", "eni", "cluster-pool", "azure"], var.ipam_mode)
    error_message = "ipam_mode must be one of: kubernetes, eni, cluster-pool, azure."
  }
}

variable "talos_mode" {
  description = "Enable Talos-specific Cilium settings: explicit Linux capabilities (instead of full privileged mode) and disabled cgroup auto-mount (Talos mounts cgroups at boot)."
  type        = bool
  default     = false
}
