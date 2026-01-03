locals {
  # Extract role from instance: use explicit role if provided, otherwise infer from instance name
  # Instances with count > 1 are named like "controlplane-0", "controlplane-1", etc.
  # If explicit role is set, use it; otherwise match against original instance names
  instance_roles = {
    for k, v in module.instances : k => (
      # First, try to use explicit role from the expanded instance
      try(local.all_instances_by_name[k].role, null) != null ?
      local.all_instances_by_name[k].role :
      # If no explicit role, try to find matching original instance name
      try([
        for orig_instance in var.instances : orig_instance.name
        if startswith(v.name, "${orig_instance.name}-") || v.name == orig_instance.name
      ][0], v.name)
    )
  }

  # Get IP address for each instance (prefer actual assigned IP, fallback to calculated)
  instance_ips = {
    for k, v in module.instances : k => (
      v.ipv4_address != null && v.ipv4_address != "" ? v.ipv4_address : (
        try(local.all_instances_by_name[k].ipv4 != null ? split("/", local.all_instances_by_name[k].ipv4)[0] : null, null)
      )
    )
  }

  # Extract hostname from instance config (user.hostname) or derive from instance name
  # When count > 1, instances are named like "controlplane-0", "controlplane-1", etc.
  # We try to extract hostname from config first, then fall back to a sensible default
  instance_hostnames = {
    for k, v in module.instances : k => (
      # Try to get hostname from config
      try(local.all_instances_by_name[k].config["user.hostname"], null) != null ?
      local.all_instances_by_name[k].config["user.hostname"] :
      # If no hostname in config, use instance name (which may be "controlplane-0", "worker-1", etc.)
      v.name
    )
  }

  # Generic instances
  instances = [
    for k, v in module.instances : {
      name     = v.name
      hostname = local.instance_hostnames[k]
      ipv4     = local.instance_ips[k]
      ipv6     = v.ipv6_address
      status   = v.status
      type     = v.type
      image    = v.image
      role     = local.instance_roles[k]
    }
  ]

  # K8s-specific outputs for Talos (controlplanes and workers with endpoint)
  controlplanes = [
    for k, v in module.instances : {
      hostname = local.instance_hostnames[k]
      endpoint = local.instance_ips[k] != null ? "${local.instance_ips[k]}:6443" : null
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = v.ipv6_address
      status   = v.status
      type     = v.type
      image    = v.image
    }
    if local.instance_roles[k] == "controlplane" && local.instance_ips[k] != null
  ]

  workers = [
    for k, v in module.instances : {
      hostname = local.instance_hostnames[k]
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = v.ipv6_address
      status   = v.status
      type     = v.type
      image    = v.image
    }
    if local.instance_roles[k] == "worker" && local.instance_ips[k] != null
  ]
}

#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "network_name" {
  description = "The name of the network being used"
  value       = local.network_name
}

output "network_type" {
  description = "The type of network. Can be one of: bridge, macvlan, sriov, ovn or physical. Null if network was not created by this module"
  value       = var.create_network ? incus_network.main[0].type : null
}

output "network_managed" {
  description = "Whether or not the network is managed. Null if network was not created by this module"
  value       = var.create_network ? incus_network.main[0].managed : null
}

output "instances" {
  description = "Flat list of all instances. Generic format with basic instance information (name, hostname, ipv4, ipv6, status, type, image, role). No k8s-specific fields."
  value       = local.instances
}

output "controlplanes" {
  description = "List of controlplane instances formatted for Talos (hostname, endpoint, node). Returns empty list if no controlplane instances exist or IPs are not yet assigned."
  value       = local.controlplanes
}

output "workers" {
  description = "List of worker instances formatted for Talos (hostname, node). Returns empty list if no worker instances exist or IPs are not yet assigned."
  value       = local.workers
}
