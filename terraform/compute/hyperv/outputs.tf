locals {
  instance_roles = {
    for k, v in hyperv_vm.instances : k => coalesce(local.instances_by_name[k].role, k)
  }

  # Declared ipv4, else the first IPv4 address the guest reports.
  instance_ips = {
    for k, v in hyperv_vm.instances : k => (
      local.instances_by_name[k].ipv4 != null ? local.instances_by_name[k].ipv4 : try([
        for ip in v.network_adapter[0].ip_addresses : ip
        if length(regexall(":", ip)) == 0
      ][0], null)
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
      name        = v.name
      hostname    = k
      ipv4        = local.instance_ips[k]
      ipv6        = local.instance_ipv6s[k]
      status      = try(v.state.current, null)
      type        = "virtual-machine"
      image       = local.instances_by_name[k].image
      role        = local.instance_roles[k]
      instance_id = v.vm_id
    }
  ]

  controlplanes = [
    for k, v in hyperv_vm.instances : {
      hostname    = k
      endpoint    = local.instance_ips[k] != null ? "${local.instance_ips[k]}:50000" : null
      node        = local.instance_ips[k]
      name        = v.name
      ipv4        = local.instance_ips[k]
      ipv6        = local.instance_ipv6s[k]
      status      = try(v.state.current, null)
      type        = "virtual-machine"
      image       = local.instances_by_name[k].image
      instance_id = v.vm_id
    }
    if local.instance_roles[k] == "controlplane" && local.instance_ips[k] != null
  ]

  workers = [
    for k, v in hyperv_vm.instances : {
      hostname    = k
      endpoint    = local.instance_ips[k] != null ? "${local.instance_ips[k]}:50000" : null
      node        = local.instance_ips[k]
      name        = v.name
      ipv4        = local.instance_ips[k]
      ipv6        = local.instance_ipv6s[k]
      status      = try(v.state.current, null)
      type        = "virtual-machine"
      image       = local.instances_by_name[k].image
      instance_id = v.vm_id
    }
    if local.instance_roles[k] == "worker" && local.instance_ips[k] != null
  ]
}

# -----------------------------------------------------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------------------------------------------------

output "network_name" {
  description = "Name of the virtual switch the VMs attach to. With switch_type ICS, the switch HNS shares across all ICS networks on the host"
  value       = local.vm_switch_name
}

output "network_type" {
  description = "Hyper-V switch type (External, Internal, Private, ICS). Null when create_network is false"
  value       = var.create_network ? var.switch_type : null
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
  description = "Map of installed TCP port proxies keyed by host listen port, valued by the guest address each one forwards to"
  value       = { for k, r in hyperv_port_proxy.tcp : k => "${r.connect_address}:${r.connect_port}" }
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
