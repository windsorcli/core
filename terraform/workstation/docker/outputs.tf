# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "network_name" {
  description = "Name of the Docker network."
  value       = docker_network.main.name
}

output "network_id" {
  description = "ID of the Docker network."
  value       = docker_network.main.id
}

output "network_cidr" {
  description = "CIDR of the Docker network (same as var.network_cidr). Used by compute/docker when attaching to this network."
  value       = var.network_cidr
}

output "compose_project" {
  description = "Docker Compose project name (workstation-windsor-{context}). Use as compute/docker compose_project so cluster containers share the same compose group."
  value       = local.compose_project
}

output "next_ip" {
  description = "First IP for sequential node assignment. Fixed at host index var.node_start_offset (default 10); stable across registry add/remove because registries fill the reserved block [4, node_start_offset). Use as compute/docker start_ip when attaching to this network."
  value       = cidrhost(var.network_cidr, var.node_start_offset)
  precondition {
    condition     = length(local.registry_keys_sorted) + (var.enable_mirror ? 1 : 0) <= local.registry_ip_capacity
    error_message = "Too many registries (${length(local.registry_keys_sorted)}${var.enable_mirror ? " + mirror" : ""}) for the reserved block of ${local.registry_ip_capacity} slots (hosts 4..${var.node_start_offset - 1}). Raise node_start_offset or drop registries."
  }
}

output "dns_ip" {
  description = "Host-facing IP for the DNS container. For docker-desktop runtime, 127.0.0.1 (ports published to localhost); otherwise cidrhost(network_cidr, 2)."
  value       = local.use_localhost_networking ? "127.0.0.1" : local.dns_ip
}

output "domain_name" {
  description = "Domain name used for DNS zone and hostnames (dns.domain_name, git.domain_name, etc.). Equal to var.domain_name when set, otherwise var.context."
  value       = local.domain_name
}

output "corefile_path" {
  description = "Path to the Corefile on the host; null when Corefile is injected into the container via upload (no host file)."
  value       = null
}

output "loadbalancer_start_ip" {
  description = "First IP in the load balancer range. Derived from network_cidr (first host of next /24) when not set. Webhook host and dns_forward_target are derived from this."
  value       = local.loadbalancer_start_ip
}

output "webhook_host" {
  description = "IP (or host) used for the git livereload webhook URL. Derived from loadbalancer_start_ip when webhook_host and primary_node_ip are not set."
  value       = local.webhook_host
}

output "service_ips" {
  description = "IPv4 addresses from network_cidr: dns=2, git=3, registries=4..(node_start_offset-1)."
  value       = local.service_ips
}

output "containers" {
  description = "Map of service name to container name: dns, git (when enabled), mirror (when enabled), and each registry key."
  value = {
    for k, v in merge(
      { dns = try(docker_container.dns[0].name, null), git = try(docker_container.git[0].name, null), mirror = try(docker_container.mirror[0].name, null) },
      { for rk, rv in docker_container.registry : rk => rv.name }
    ) : k => v if v != null
  }
}

output "mirror_hostname" {
  description = "Hostname of the mirror registry container. Null when enable_mirror is false."
  value       = var.enable_mirror ? local.mirror_hostname : null
}

output "registries" {
  description = "Registry config with computed hostname per entry. Merges var.registries with hostname (e.g. gcr.domain_name) for cluster Talos mirrors and other consumers."
  value = {
    for k in keys(local.registries) : k => {
      remote   = try(local.registries[k].remote, null)
      local    = try(trimprefix(trimprefix(local.registries[k].local, "https://"), "http://"), null)
      hostport = try(local.registries[k].hostport, null)
      hostname = "${local.registry_host_prefix[k]}.${local.domain_name}"
    }
  }
}
