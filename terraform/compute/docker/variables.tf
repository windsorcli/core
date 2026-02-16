# -----------------------------------------------------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------------------------------------------------

variable "context" {
  description = "The windsor context id for this deployment. Typically set implicitly via TF_VAR_context; no need to pass in facet inputs."
  type        = string
  default     = ""
}

variable "context_id" {
  description = "The windsor context id for this deployment. Typically set implicitly via TF_VAR_context; no need to pass in facet inputs."
  type        = string
  default     = ""
}

variable "project_root" {
  description = "Project root path for bind mounts (e.g. Talos /var/mnt/local). When set, facets can pass project_root + '/.volumes:/var/mnt/local' in instance volumes."
  type        = string
  default     = null
}

variable "network_name" {
  description = "Name of the network to use. When create_network is false (e.g. attaching to workstation network), use terraform_output(workstation, network_name). When create_network is true this network is created; empty defaults to windsor-{context}."
  type        = string
  default     = ""
}

variable "create_network" {
  description = "Whether to create the network. If false, network_name must reference an existing network"
  type        = bool
  default     = true
}

variable "network_driver" {
  description = "Docker network driver (bridge, overlay, etc.)"
  type        = string
  default     = "bridge"
}

variable "runtime" {
  description = "Docker host runtime: docker-desktop (localhost-only networking, no VM control) or colima/linux (advanced networking, IP routing). Use 'colima' as alias for 'linux'. Standardized with workstation/docker."
  type        = string
  default     = "linux"

  validation {
    condition     = contains(["docker-desktop", "linux", "colima"], var.runtime)
    error_message = "runtime must be one of: docker-desktop, linux, colima (colima is alias for linux)"
  }
}

variable "network_cidr" {
  description = "CIDR of the network. When create_network is false (e.g. workstation), use terraform_output(workstation, network_cidr). When set with start_ip, containers get sequential IPs from start_ip."
  type        = string
  default     = null
}

variable "start_ip" {
  description = "First container IP for sequential assignment. When create_network is false (e.g. workstation), use terraform_output(workstation, next_ip). With network_cidr, all containers get sequential IPs from this address."
  type        = string
  default     = null
}

variable "compose_project" {
  description = "Docker Compose project name (e.g. terraform_output(workstation, compose_project)). When set, containers get label com.docker.compose.project so they appear in the same compose group."
  type        = string
  default     = null
}

variable "cluster_nodes" {
  description = "Declare controlplanes and workers by count and image. Module expands to N+M containers; shape (ports, volumes, env) is chosen by distribution. hostports: first controlplane gets controlplanes.hostports when no workers, else first worker gets workers.hostports."
  type = object({
    distribution = optional(string, "talos")
    controlplanes = object({
      count     = number
      image     = string
      cpu       = optional(number, 2)
      memory    = optional(number, 2)        # GB
      volumes   = optional(list(string), []) # source:dest; source = host path (/ or .) for bind mount, or volume name for named volume. Appended to distribution shape.
      hostports = optional(list(string), []) # host:container/protocol. Applied to first controlplane when no workers (primary node).
    })
    workers = object({
      count     = number
      image     = string
      cpu       = optional(number, 4)
      memory    = optional(number, 4)        # GB
      volumes   = optional(list(string), []) # source:dest; host path or named volume. Appended to distribution shape.
      hostports = optional(list(string), []) # host:container/protocol. Applied to first worker when workers exist (primary node).
    })
  })
  default = null

  validation {
    condition     = var.cluster_nodes == null || contains(["talos"], var.cluster_nodes.distribution)
    error_message = "cluster_nodes.distribution must be \"talos\" (k3s etc. reserved for future use)."
  }
}

variable "instances" {
  description = "List of instance definitions. Used in addition to cluster_nodes when both are set. Each object specifies container parameters such as image, count, ports, volumes, environment variables, networks, and other optional settings."
  type = list(object({
    name         = string # Instance/container name (prefix when count > 1, then -0, -1, ...)
    image        = string # Image reference (e.g. nginx:alpine)
    count        = optional(number, 1)
    role         = optional(string)           # Role for outputs (e.g. controlplane, worker)
    ports        = optional(list(string), []) # "host:container/protocol" or "container/protocol" (e.g. 50000/tcp, 8080:30080/tcp, 8053:30053/udp)
    volumes      = optional(list(string), []) # "host:container" or "volume_name:container"; volume_name may contain {container_name}, {instance_name}, {index}, {index_1}
    env          = optional(map(string), {})
    networks     = optional(list(string), []) # Network names; empty = default network
    command      = optional(list(string))
    entrypoint   = optional(list(string))
    restart      = optional(string, "unless-stopped")
    labels       = optional(map(string), {})
    hostname     = optional(string) # May contain {container_name}, {instance_name}, {index}, {index_1} (1-based)
    privileged   = optional(bool, false)
    read_only    = optional(bool, false)
    security_opt = optional(list(string), []) # e.g. ["seccomp=unconfined"]
    tmpfs        = optional(map(string), {})  # path -> options (e.g. { "/run" = "", "/tmp" = "" })
    ipv4_address = optional(string)
    healthcheck = optional(object({
      test         = list(string) # e.g. ["CMD", "curl", "-f", "http://localhost/"]
      interval     = optional(string, "30s")
      timeout      = optional(string, "10s")
      retries      = optional(number, 3)
      start_period = optional(string, "0s")
    }))
    depends_on = optional(list(string), []) # Other instance names (creation order)
  }))
  default = []

  validation {
    condition     = alltrue([for i in var.instances : contains(["no", "on-failure", "always", "unless-stopped"], i.restart)])
    error_message = "Instance restart must be one of: no, on-failure, always, unless-stopped"
  }
}
