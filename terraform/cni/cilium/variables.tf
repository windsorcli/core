variable "cilium_version" {
  description = "Version of the Cilium Helm chart to install."
  type        = string
  # renovate: datasource=helm depName=cilium package=cilium helmRepo=https://helm.cilium.io
  default = "1.19.3"
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
