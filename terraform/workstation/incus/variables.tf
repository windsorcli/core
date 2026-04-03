# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_root" {
  description = "Absolute path to the project root. Used for bind mounts (Corefile, .windsor/cache, repo). Universal variable provided by the environment."
  type        = string
}

variable "context" {
  description = "Windsor context name (e.g. local, test). Used for network name and instance names; container names use domain_name (which defaults to context). Universal variable provided by the environment."
  type        = string
}

variable "domain_name" {
  description = "Domain name used for DNS zone and hostnames in the Corefile (e.g. dns.domain_name, git.domain_name). Defaults to context when not set."
  type        = string
  default     = null
}

variable "network_name" {
  description = "Name of the Incus bridge network. When create_network is true, defaults to windsor-{context}. When create_network is false, must be the existing network (e.g. incusbr0 for Colima)."
  type        = string
  default     = null
}

variable "create_network" {
  description = "Whether to create the Incus network. If false, use network_name as existing network (e.g. incusbr0 when runtime is colima)."
  type        = bool
  default     = true
}

variable "network_cidr" {
  description = "CIDR for the Incus network (e.g. 10.5.0.0/16). Service IPs are assigned sequentially: 1=gateway, 2=dns, 3=git, 4+=registries. Corefile, load balancer subnet, and webhook host are derived from this."
  type        = string
  default     = "10.5.0.0/16"
}

variable "loadbalancer_start_ip" {
  description = "First IP in the load balancer range (e.g. 10.5.1.1). Used to derive webhook_host and dns_forward_target when not overridden. If null, derived as first host of next /24 from network_cidr."
  type        = string
  default     = null
}

variable "webhook_host" {
  description = "IP (or host) for the git livereload webhook URL. If null, derived from loadbalancer_start_ip."
  type        = string
  default     = null
}

variable "webhook_port" {
  description = "Port for the git livereload webhook URL."
  type        = number
  default     = 9292
}

variable "webhook_enabled" {
  description = "Enable git livereload webhook notifications."
  type        = bool
  default     = true
}

variable "primary_node_ip" {
  description = "IP of the primary developing node (controlplane or worker) for NodePort webhook. If set and webhook_host is null, used as webhook host."
  type        = string
  default     = null
}

variable "dns_forward_target" {
  description = "Target for Corefile forward directive (context zone). If null, uses loadbalancer_start_ip."
  type        = string
  default     = null
}

variable "enable_dns" {
  description = "Create the DNS (CoreDNS) container."
  type        = bool
  default     = true
}

variable "enable_git" {
  description = "Create the git livereload container."
  type        = bool
  default     = true
}

variable "registries" {
  description = "Map of registry configs (aligned with windsor docker.registries). Key is registry host (e.g. gcr.io, registry.k8s.io). Each entry: remote (proxy upstream URL), hostport (unused for Incus; kept for API compatibility), local. Omit remote for local-only registry."
  type = map(object({
    remote   = optional(string)
    local    = optional(string)
    hostport = optional(number)
  }))
  default = {
    "gcr.io" = {
      remote = "https://gcr.io"
    }
    "ghcr.io" = {
      remote = "https://ghcr.io"
    }
    "quay.io" = {
      remote = "https://quay.io"
    }
    "registry-1.docker.io" = {
      remote = "https://registry-1.docker.io"
      local  = "docker.io"
    }
    "registry.k8s.io" = {
      remote = "https://registry.k8s.io"
    }
    registry = {
      hostport = 5001
    }
  }
}

variable "webhook_token" {
  description = "Raw token for the Flux Receiver secret. The webhook URL is derived by hashing this with the receiver name and namespace."
  type        = string
  default     = "abcdef123456"
  sensitive   = true
}

variable "receiver_name" {
  description = "Name of the Flux Receiver resource used to compute the webhook URL path."
  type        = string
  default     = "flux-webhook"
}

variable "receiver_namespace" {
  description = "Namespace of the Flux Receiver resource used to compute the webhook URL path."
  type        = string
  default     = "system-gitops"
}

variable "git_username" {
  description = "Username for git livereload HTTP auth. Defaults to local."
  type        = string
  default     = "local"
}

variable "git_password" {
  description = "Password for git livereload HTTP auth. Defaults to local."
  type        = string
  default     = "local"
  sensitive   = true
}

variable "git_rsync_exclude" {
  description = "Comma-separated list of paths to exclude from rsync (git livereload)."
  type        = string
  default     = ".windsor,.terraform,.volumes,.venv"
}

variable "git_rsync_include" {
  description = "Comma-separated list of paths to include in rsync (git livereload)."
  type        = string
  default     = "kustomize"
}

variable "git_rsync_protect" {
  description = "Comma-separated list of paths to protect from deletion in rsync (git livereload)."
  type        = string
  default     = "flux-system"
}
