variable "cilium_version" {
  description = "Version of the Cilium Helm chart to install."
  type        = string
  # renovate: datasource=docker depName=quay.io/cilium/charts/cilium package=quay.io/cilium/charts/cilium
  default = "1.20.3"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cilium_version))
    error_message = "cilium_version must be in X.Y.Z format."
  }
}

variable "k8s_service_host" {
  description = "API server host Cilium reaches before its eBPF service rules are active. Required when kube_proxy_replacement is true."
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[A-Za-z0-9.-]*$", var.k8s_service_host))
    error_message = "k8s_service_host must be a hostname or IPv4 address, without scheme or port."
  }
}

variable "k8s_service_port" {
  description = "API server port for k8s_service_host."
  type        = number
  default     = 6443
  validation {
    condition     = var.k8s_service_port >= 1 && var.k8s_service_port <= 65535
    error_message = "k8s_service_port must be between 1 and 65535."
  }
}

variable "kube_proxy_replacement" {
  description = "Replace kube-proxy with Cilium's eBPF implementation. Requires k8s_service_host to be set. Recommended for Talos."
  type        = bool
  default     = true
}

variable "ipam_mode" {
  description = "Cilium IPAM mode. 'kubernetes' uses node CIDR ranges (default, works for Talos). 'eni' uses AWS ENI-based allocation for EKS native networking."
  type        = string
  default     = "kubernetes"
  validation {
    condition     = contains(["kubernetes", "eni", "cluster-pool", "azure"], var.ipam_mode)
    error_message = "ipam_mode must be one of: kubernetes, eni, cluster-pool, azure."
  }
}

variable "privileged" {
  description = "Run the Cilium agent as a privileged container (chart default). Set to false on systems that forbid privileged pods (Talos, hardened distros); the agent will run with an explicit set of Linux capabilities instead."
  type        = bool
  default     = true
}

variable "cgroup_auto_mount" {
  description = "Let Cilium mount the cgroup2 fs at startup (chart default). Set to false on systems that mount cgroups during init (Talos, most systemd-based distros on recent kernels) so Cilium uses the pre-mounted path instead of racing to mount its own."
  type        = bool
  default     = true
}

variable "operator_replicas" {
  description = "Cilium operator replica count. Keep aligned with the Flux-managed HelmRelease so re-runs of this bootstrap don't scale the deployment up or down between Flux reconciles. 1 on physically single-node clusters (operator binds a hostPort, so two replicas can't co-schedule); 2 elsewhere for controller redundancy."
  type        = number
  default     = 2
  validation {
    condition     = var.operator_replicas >= 1 && var.operator_replicas <= 3
    error_message = "operator_replicas must be between 1 and 3."
  }
}
