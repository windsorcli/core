# The Docker Workstation module creates Windsor local-development containers using the Docker provider.
# It provisions a bridge network and containers for DNS, registries, and git livereload.
# Supports docker-desktop (published ports) and linux (Colima, native Linux, containerd) drivers. Does not create Talos controlplane containers.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">=1.8"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  context_path_resolved = coalesce(var.context_path, var.project_root)
  domain_name           = coalesce(var.domain_name, var.context)
  compose_project       = "workstation-windsor-${var.context}"
  network_name_resolved = coalesce(var.network_name, "windsor-${var.context}")
  # Runtime: docker-desktop => localhost-only networking; colima/linux => advanced networking. Standardized with compute/docker.
  runtime                  = (var.runtime == "colima" || var.runtime == "docker") ? "linux" : var.runtime
  use_localhost_networking = local.runtime == "docker-desktop"
  publish_ports            = local.use_localhost_networking
  # Load balancer start IP: explicit or first host of next /24 from network_cidr
  loadbalancer_start_ip = coalesce(var.loadbalancer_start_ip, cidrhost(cidrsubnet(var.network_cidr, 8, 1), 1))
  # /24 containing loadbalancer_start_ip (for docker-desktop host 10)
  loadbalancer_cidr = "${join(".", concat(slice(split(".", local.loadbalancer_start_ip), 0, 3), ["0"]))}/24"
  # Webhook host: explicit, or primary node IP, or primary LB (localhost mode=host 10 in same /24, else loadbalancer_start_ip)
  webhook_host_derived = local.use_localhost_networking ? cidrhost(local.loadbalancer_cidr, 10) : local.loadbalancer_start_ip
  webhook_host         = coalesce(var.webhook_host, var.primary_node_ip, local.webhook_host_derived)
  webhook_url          = "http://${local.webhook_host}:9292/hook/${var.webhook_token}"
  common_labels = [
    { label = "context", value = var.context },
    { label = "managed_by", value = "terraform" }
  ]
  # Sequential from lowest block: 1=gateway (not a container), 2=dns, 3=git, 4+=registries
  gateway              = cidrhost(var.network_cidr, 1)
  dns_ip               = cidrhost(var.network_cidr, 2)
  git_ip               = cidrhost(var.network_cidr, 3)
  registry_keys_sorted = sort(keys(var.registries))
  registry_ips = {
    for i, k in local.registry_keys_sorted : k => cidrhost(var.network_cidr, 4 + i)
  }
  service_ips = merge(
    { dns = local.dns_ip, git = local.git_ip },
    local.registry_ips
  )
  # Corefile forward: localhost mode = gateway:8053, else loadbalancer_start_ip
  dns_forward_target = coalesce(var.dns_forward_target, local.use_localhost_networking ? "${local.gateway}:8053" : local.loadbalancer_start_ip)

  # Corefile hosts: localhost mode uses 127.0.0.1 (host via published ports), else CIDR-derived IPs
  corefile_host_entries = concat(
    var.enable_dns ? ["${local.use_localhost_networking ? "127.0.0.1" : local.dns_ip} dns.${local.domain_name}"] : [],
    [for k in local.registry_keys_sorted : "${local.use_localhost_networking ? "127.0.0.1" : local.registry_ips[k]} ${k}.${local.domain_name}"],
    var.enable_git ? ["${local.use_localhost_networking ? "127.0.0.1" : local.git_ip} git.${local.domain_name}"] : []
  )
  corefile_content = var.enable_dns ? templatefile("${path.module}/templates/Corefile.tpl", {
    context            = local.domain_name
    host_entries       = local.corefile_host_entries
    dns_forward_target = local.dns_forward_target
  }) : ""
}

# =============================================================================
# Network
# =============================================================================

resource "docker_network" "main" {
  name       = local.network_name_resolved
  driver     = "bridge"
  attachable = false
  ingress    = false
  internal   = false
  ipv6       = false
  # Allow host (e.g. macOS via Colima VM) to reach container IPs directly; required when
  # host is not the Docker host. Same option used by docker-compose in local context.
  # Supported on Colima, Docker Desktop (Linux VM), and native Docker (Linux). Tradeoff:
  # containers are reachable at their bridge IPs from the host/LAN without port publishing.
  options = {
    "com.docker.network.bridge.gateway_mode_ipv4" = "nat-unprotected"
  }
  labels {
    label = "com.docker.compose.project"
    value = local.compose_project
  }
  ipam_config {
    subnet  = var.network_cidr
    gateway = local.gateway
  }
  # Docker returns computed/read-only attributes (options.enable_ipv4/ipv6, ipam_config.aux_address, scope, ipam_options) that cause perpetual replace when not ignored.
  lifecycle {
    ignore_changes = [
      "ipam_options",
      "options",
      "ipam_config",
      "scope",
    ]
  }
}

# =============================================================================
# Images
# =============================================================================

resource "docker_image" "coredns" {
  count = var.enable_dns ? 1 : 0
  name  = "coredns/coredns:1.14.1"
}

resource "docker_image" "git_livereload" {
  count = var.enable_git ? 1 : 0
  name  = "ghcr.io/windsorcli/git-livereload:v0.2.1"
}

# =============================================================================
# Container: dns
# =============================================================================

resource "docker_container" "dns" {
  count   = var.enable_dns ? 1 : 0
  name    = "dns.${local.domain_name}"
  image   = docker_image.coredns[0].image_id
  command = ["-conf", "/etc/coredns/Corefile"]
  restart = "always"
  labels {
    label = "context"
    value = var.context
  }
  labels {
    label = "managed_by"
    value = "terraform"
  }
  labels {
    label = "role"
    value = "dns"
  }
  labels {
    label = "com.docker.compose.project"
    value = local.compose_project
  }
  dynamic "ports" {
    for_each = local.publish_ports ? [1] : []
    content {
      internal = 53
      external = 53
      protocol = "tcp"
    }
  }
  dynamic "ports" {
    for_each = local.publish_ports ? [1] : []
    content {
      internal = 53
      external = 53
      protocol = "udp"
    }
  }
  networks_advanced {
    name         = docker_network.main.name
    ipv4_address = local.dns_ip
  }
  upload {
    content = local.corefile_content
    file    = "/etc/coredns/Corefile"
  }
}

# =============================================================================
# Containers: registries (from var.registries)
# =============================================================================

resource "docker_image" "registry" {
  count = length(var.registries) > 0 ? 1 : 0
  name  = "registry:3.0.0"
}

resource "docker_container" "registry" {
  for_each = var.registries
  name     = "${each.key}.${local.domain_name}"
  image    = docker_image.registry[0].image_id
  restart  = "always"
  labels {
    label = "context"
    value = var.context
  }
  labels {
    label = "managed_by"
    value = "terraform"
  }
  labels {
    label = "role"
    value = "registry"
  }
  labels {
    label = "com.docker.compose.project"
    value = local.compose_project
  }
  env = concat(
    each.value.remote != null ? ["REGISTRY_PROXY_REMOTEURL=${each.value.remote}"] : [],
    each.value.local != null ? ["REGISTRY_PROXY_LOCALURL=${each.value.local}"] : []
  )
  dynamic "ports" {
    for_each = each.value.hostport != null && local.publish_ports ? [1] : []
    content {
      internal = 5000
      external = each.value.hostport
      protocol = "tcp"
    }
  }
  networks_advanced {
    name         = docker_network.main.name
    ipv4_address = local.registry_ips[each.key]
  }
  volumes {
    host_path      = "${var.project_root}/.windsor/cache/docker"
    container_path = "/var/lib/registry"
  }
}

# =============================================================================
# Container: git
# =============================================================================

resource "docker_container" "git" {
  count = var.enable_git ? 1 : 0
  name  = "git.${local.domain_name}"
  image = docker_image.git_livereload[0].image_id
  env = [
    "GIT_PASSWORD=${var.git_password}",
    "GIT_USERNAME=${var.git_username}",
    "RSYNC_EXCLUDE=${var.git_rsync_exclude}",
    "RSYNC_INCLUDE=${var.git_rsync_include}",
    "RSYNC_PROTECT=${var.git_rsync_protect}",
    "VERIFY_SSL=false",
    "WEBHOOK_URL=${local.webhook_url}"
  ]
  restart = "always"
  labels {
    label = "context"
    value = var.context
  }
  labels {
    label = "managed_by"
    value = "terraform"
  }
  labels {
    label = "role"
    value = "git-repository"
  }
  labels {
    label = "com.docker.compose.project"
    value = local.compose_project
  }
  networks_advanced {
    name         = docker_network.main.name
    ipv4_address = local.git_ip
  }
  volumes {
    host_path      = var.project_root
    container_path = "/repos/mount/core"
  }
}
