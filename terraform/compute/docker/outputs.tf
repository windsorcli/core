# -----------------------------------------------------------------------------------------------------------------------
# Locals for outputs (aligned with compute/incus; consumed by cluster/talos via provider-docker)
# -----------------------------------------------------------------------------------------------------------------------

locals {
  # IPv4 per container: computed static or from container network_data after apply
  instance_ips = {
    for k, v in docker_container.containers : k => coalesce(
      try(local.container_ipv4[k] != null ? split("/", local.container_ipv4[k])[0] : null, null),
      try([for nd in v.network_data : nd.ip_address if nd.network_name == local.network_name][0], null)
    )
  }

  # Hostname: instance hostname or container name
  instance_hostnames = {
    for k, v in docker_container.containers : k => coalesce(
      try(local.containers_by_name[k].hostname, null),
      v.name
    )
  }

  # Role from instance config (for controlplanes/workers filtering)
  instance_roles = {
    for k, v in docker_container.containers : k => try(local.containers_by_name[k].role, null)
  }

  # docker-desktop: endpoint = 127.0.0.1:host_port (cp1=50000, ...). Colima/linux: endpoint = node_ip:50000 (host reachable via route).
  _cp_keys_sorted     = sort([for k, v in docker_container.containers : k if local.instance_roles[k] == "controlplane"])
  _worker_keys_sorted = sort([for k, v in docker_container.containers : k if local.instance_roles[k] == "worker"])
  _host_port_cp       = { for i, k in local._cp_keys_sorted : k => 50000 + i }
  _host_port_worker   = { for i, k in local._worker_keys_sorted : k => 50000 + length(local._cp_keys_sorted) + i }
  _endpoint_cp        = { for k in local._cp_keys_sorted : k => (local.use_localhost_networking ? "127.0.0.1:${local._host_port_cp[k]}" : "${local.instance_ips[k]}:50000") }
  _endpoint_worker    = { for k in local._worker_keys_sorted : k => (local.use_localhost_networking ? "127.0.0.1:${local._host_port_worker[k]}" : "${local.instance_ips[k]}:50000") }

  # Generic instances list (same shape as compute/incus)
  instances = [
    for k, v in docker_container.containers : {
      name     = v.name
      hostname = local.instance_hostnames[k]
      ipv4     = local.instance_ips[k]
      ipv6     = null
      status   = null
      type     = "container"
      image    = local.containers_by_name[k].image
      role     = local.instance_roles[k]
    }
  ]

  # Controlplanes for cluster/talos (hostname, endpoint, node; role == "controlplane"). Endpoint host-reachable when docker-desktop.
  controlplanes = [
    for k, v in docker_container.containers : {
      hostname = local.instance_hostnames[k]
      endpoint = local.instance_ips[k] != null ? local._endpoint_cp[k] : null
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = null
      status   = null
      type     = "container"
      image    = local.containers_by_name[k].image
    }
    if local.instance_roles[k] == "controlplane" && local.instance_ips[k] != null
  ]

  # Workers for cluster/talos (same shape)
  workers = [
    for k, v in docker_container.containers : {
      hostname = local.instance_hostnames[k]
      endpoint = local.instance_ips[k] != null ? local._endpoint_worker[k] : null
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = null
      status   = null
      type     = "container"
      image    = local.containers_by_name[k].image
    }
    if local.instance_roles[k] == "worker" && local.instance_ips[k] != null
  ]
}

# -----------------------------------------------------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------------------------------------------------

output "network_name" {
  description = "The name of the network being used"
  value       = local.network_name
}

output "network_type" {
  description = "The network driver when create_network is true (e.g. bridge). Null if network was not created by this module"
  value       = var.create_network ? var.network_driver : null
}

output "network_managed" {
  description = "Whether the network was created by this module (true when create_network is true)"
  value       = var.create_network
}

output "instances" {
  description = "Flat list of all instances. Same shape as compute/incus (name, hostname, ipv4, ipv6, status, type, image, role)."
  value       = local.instances
}

output "controlplanes" {
  description = "List of controlplane instances for cluster/talos (hostname, endpoint, node). Consumed by provider-docker → cluster/talos when workstation enabled."
  value       = local.controlplanes
}

output "workers" {
  description = "List of worker instances for cluster/talos (hostname, endpoint, node). Consumed by provider-docker → cluster/talos when workstation enabled."
  value       = local.workers
}
