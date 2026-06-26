locals {
  instance_roles = {
    for k, v in hyperv_vm.instances : k => coalesce(local.instances_by_name[k].role, k)
  }

  # Hyper-V reports per-NIC IPs through integration services; the first IPv4
  # surfaces only after the VM is Running and the guest has booted. Fall back
  # to the user-declared ipv4 (with count expansion already applied) when the
  # guest hasn't reported one yet.
  instance_ips = {
    for k, v in hyperv_vm.instances : k => (
      try(length(v.network_adapter[0].ip_addresses) > 0 ? [
        for ip in v.network_adapter[0].ip_addresses : ip
        if length(regexall(":", ip)) == 0
      ][0] : null, null) != null
      ? try([
        for ip in v.network_adapter[0].ip_addresses : ip
        if length(regexall(":", ip)) == 0
      ][0], null)
      : local.instances_by_name[k].ipv4
    )
  }

  instance_ipv6s = {
    for k, v in hyperv_vm.instances : k => (
      try([
        for ip in v.network_adapter[0].ip_addresses : ip
        if length(regexall(":", ip)) > 0
      ][0], null)
    )
  }

  instances = [
    for k, v in hyperv_vm.instances : {
      name     = v.name
      hostname = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = local.instance_ipv6s[k]
      status   = try(v.state.current, null)
      type     = "virtual-machine"
      image    = local.instances_by_name[k].image
      role     = local.instance_roles[k]
    }
  ]

  controlplanes = [
    for k, v in hyperv_vm.instances : {
      hostname = v.name
      endpoint = local.instance_ips[k] != null ? "${local.instance_ips[k]}:50000" : null
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = local.instance_ipv6s[k]
      status   = try(v.state.current, null)
      type     = "virtual-machine"
      image    = local.instances_by_name[k].image
    }
    if local.instance_roles[k] == "controlplane" && local.instance_ips[k] != null
  ]

  workers = [
    for k, v in hyperv_vm.instances : {
      hostname = v.name
      endpoint = local.instance_ips[k] != null ? "${local.instance_ips[k]}:50000" : null
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = local.instance_ipv6s[k]
      status   = try(v.state.current, null)
      type     = "virtual-machine"
      image    = local.instances_by_name[k].image
    }
    if local.instance_roles[k] == "worker" && local.instance_ips[k] != null
  ]
}

# -----------------------------------------------------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------------------------------------------------

output "network_name" {
  description = "Name of the virtual switch the VMs attach to"
  value       = local.network_name
}

output "network_type" {
  description = "Hyper-V switch type (External, Internal, Private). Null when create_network is false"
  value       = var.create_network ? hyperv_virtual_switch.main[0].switch_type : null
}

output "network_managed" {
  description = "True when the virtual switch was created by this module"
  value       = var.create_network
}

output "instances" {
  description = "Flat list of all VMs. Generic shape (name, hostname, ipv4, ipv6, status, type, image, role) matching compute/incus and compute/docker"
  value       = local.instances
}

output "controlplanes" {
  description = "Controlplane VMs formatted for cluster/talos (hostname, endpoint, node). Empty list until the guest reports an IP via Hyper-V integration services"
  value       = local.controlplanes
}

output "workers" {
  description = "Worker VMs formatted for cluster/talos (hostname, endpoint, node). Empty list until the guest reports an IP via Hyper-V integration services"
  value       = local.workers
}

output "tcp_port_forwards" {
  description = "Map of installed TCP NAT port forwards keyed by bench-side external_port. Empty when no port_forwards are configured (e.g. non-NAT switch types)"
  value       = { for k, r in hyperv_nat_static_mapping.tcp : k => r.id }
}

output "udp_port_forwards" {
  description = "Map of installed UDP NAT port forwards keyed by bench-side external_port"
  value       = { for k, r in hyperv_nat_static_mapping.udp : k => r.id }
}

output "machine_secrets" {
  description = "Talos cluster identity. Pass to cluster/talos as var.machine_secrets so it shares the same cluster CA."
  value       = length(talos_machine_secrets.this) > 0 ? talos_machine_secrets.this[0].machine_secrets : null
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration (CA cert + admin cert/key). Pass to cluster/talos as var.client_configuration."
  value       = length(talos_machine_secrets.this) > 0 ? talos_machine_secrets.this[0].client_configuration : null
  sensitive   = true
}
