# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "network_name" {
  description = "Name of the Incus network (created or existing when create_network is false)."
  value       = local.attached_network
}

output "network_cidr" {
  description = "CIDR of the Incus network (same as var.network_cidr). Used by compute/incus when attaching to this network."
  value       = var.network_cidr
}

output "compose_project" {
  description = "Compose project name (workstation-windsor-{context}). Kept for API compatibility with workstation/docker; compute/incus does not use it."
  value       = local.compose_project
}

output "next_ip" {
  description = "First IP for sequential node assignment. Fixed at host index var.node_start_offset (default 10); stable across registry add/remove because registries fill the reserved block [4, node_start_offset). Use as compute/incus start offset when attaching to this network."
  value       = cidrhost(var.network_cidr, var.node_start_offset)
  precondition {
    condition     = length(local.registry_keys_sorted) + (var.enable_mirror ? 1 : 0) <= local.registry_ip_capacity
    error_message = "Too many registries (${length(local.registry_keys_sorted)}${var.enable_mirror ? " + mirror" : ""}) for the reserved block of ${local.registry_ip_capacity} slots (hosts 4..${var.node_start_offset - 1}). Raise node_start_offset or drop registries."
  }
}

output "dns_ip" {
  description = "IPv4 address reserved for the DNS container (cidrhost(network_cidr, 2)). Present in service_ips.dns when enable_dns is true."
  value       = local.dns_ip
}

output "domain_name" {
  description = "Domain name used for DNS zone and hostnames (dns.domain_name, git.domain_name, etc.). Equal to var.domain_name when set, otherwise var.context."
  value       = local.domain_name
}

output "corefile_path" {
  description = "Path to the Corefile on the host (project_root/.windsor/Corefile). Written by Terraform when enable_dns is true."
  value       = local.corefile_path
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
  description = "IPv4 addresses from network_cidr (sequential: dns=2, git=3, registries=4+)."
  value       = local.service_ips
}

output "containers" {
  description = "Map of service name to instance name: dns, git (when enabled), mirror (when enabled), and each registry key."
  value = {
    for k, v in merge(
      { dns = try(incus_instance.dns[0].name, null), git = try(incus_instance.git[0].name, null), mirror = try(incus_instance.mirror[0].name, null) },
      { for rk, rv in incus_instance.registry : rk => rv.name }
    ) : k => v if v != null
  }
}

output "mirror_hostname" {
  description = "Hostname of the mirror registry instance. Null when enable_mirror is false."
  value       = var.enable_mirror ? local.mirror_hostname : null
}

output "registries" {
  description = "Registry config with computed hostname per entry. Same shape as workstation/docker for cluster Talos mirrors."
  value = {
    for k in keys(var.registries) : k => {
      remote   = try(var.registries[k].remote, null)
      local    = try(trimprefix(trimprefix(var.registries[k].local, "https://"), "http://"), null)
      hostport = try(var.registries[k].hostport, null)
      hostname = local.registry_hostname[k]
    }
  }
}
