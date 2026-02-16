# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_root" {
  description = "Absolute path to the project root. Used for bind mounts (e.g. .volumes, .windsor, repo). Universal variable provided by the environment."
  type        = string
}

variable "context" {
  description = "Windsor context name (e.g. local, test). Used for compose_project and labels; container names use domain_name (which defaults to context). Universal variable provided by the environment."
  type        = string
}

variable "context_path" {
  description = "Path to the context directory. Used to resolve .windsor config (e.g. Corefile). Defaults to project_root when not set. Universal variable provided by the environment."
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Domain name used for DNS zone and hostnames in the Corefile (e.g. dns.domain_name, git.domain_name). Defaults to context when not set."
  type        = string
  default     = null
}

variable "runtime" {
  description = "Docker host runtime: docker-desktop (localhost-only networking), colima/docker/linux (advanced networking). 'colima' and 'docker' are aliases for 'linux'. Standardized with compute/docker."
  type        = string
  default     = "docker-desktop"
  validation {
    condition     = contains(["docker-desktop", "linux", "colima", "docker"], var.runtime)
    error_message = "runtime must be one of: docker-desktop, linux, colima, docker"
  }
}

variable "network_name" {
  description = "Name of the Docker network for workstation containers. Defaults to windsor-{context} when not set."
  type        = string
  default     = null
}

variable "network_cidr" {
  description = "CIDR for the Docker network (e.g. 10.5.0.0/16). Service IPs are assigned sequentially from the lowest block: 1=gateway, 2=dns, 3=git, 4+=registries. Corefile, load balancer subnet, and webhook host are derived from this."
  type        = string
  default     = "10.5.0.0/16"
}

variable "loadbalancer_start_ip" {
  description = "First IP in the load balancer range (e.g. 10.5.1.1). Used to derive webhook_host and dns_forward_target when not overridden. If null, derived as first host of next /24 from network_cidr."
  type        = string
  default     = null
}

variable "webhook_host" {
  description = "IP (or host) for the git livereload webhook URL. Primary load balancer IP or primary developing node IP. If null, derived from loadbalancer_start_ip: linux (or colima) = loadbalancer_start_ip, docker-desktop = host 10 in same /24 (e.g. 10.5.1.10)."
  type        = string
  default     = null
}

variable "primary_node_ip" {
  description = "IP of the primary developing node (controlplane or worker) for NodePort webhook. If set and webhook_host is null, used as webhook host."
  type        = string
  default     = null
}

variable "dns_forward_target" {
  description = "Target for Corefile forward directive (context zone). If null: linux uses loadbalancer_start_ip, docker-desktop uses gateway:8053."
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
  description = "Map of registry configs (aligned with windsor docker.registries). Key is hostname prefix (e.g. gcr, registry.k8s). Each entry: remote (proxy upstream URL), local (proxy local URL, optional), hostport (publish port on host, optional). Omit remote for local-only registry."
  type = map(object({
    remote   = optional(string)
    local    = optional(string)
    hostport = optional(number)
  }))
  default = {
    gcr = {
      remote = "https://gcr.io"
    }
    ghcr = {
      remote = "https://ghcr.io"
    }
    quay = {
      remote = "https://quay.io"
    }
    "registry-1.docker" = {
      remote = "https://registry-1.docker.io"
      local  = "https://docker.io"
    }
    "registry.k8s" = {
      remote = "https://registry.k8s.io"
    }
    registry = {
      hostport = 5001
    }
  }
}

variable "webhook_token" {
  description = "Token for the git livereload webhook URL. If not set, a placeholder is used (caller should replace or provide via env)."
  type        = string
  default     = "5dc88e45e809fb0872b749c0969067e2c1fd142e17aed07573fad20553cc0c59"
  sensitive   = true
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
