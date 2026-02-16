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
  description = "Next available IP for sequential node assignment (cidrhost(network_cidr, 10)). Use as compute/docker start_ip when attaching to this network."
  value       = cidrhost(var.network_cidr, 10)
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
  description = "IPv4 addresses from network_cidr (sequential: dns=2, git=3, registries=4+)."
  value       = local.service_ips
}

output "containers" {
  description = "Map of service name to container name: dns, git (when enabled), and each registry key."
  value = {
    for k, v in merge(
      { dns = try(docker_container.dns[0].name, null), git = try(docker_container.git[0].name, null) },
      { for rk, rv in docker_container.registry : rk => rv.name }
    ) : k => v if v != null
  }
}
