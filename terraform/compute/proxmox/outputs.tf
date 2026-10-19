# -----------------------------------------------------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------------------------------------------------

output "network_name" {
  description = "Bridge the VMs are attached to"
  value       = var.network_bridge
}

output "instances" {
  description = "Flat list of all VMs. Generic shape (name, hostname, ipv4, ipv6, status, type, image, role, instance_id) matching compute/vsphere and compute/hyperv"
  value       = local.instances_output
}

output "controlplanes" {
  description = "Controlplane VMs formatted for cluster/talos (hostname, endpoint, node, config_patches). DHCP guests appear once qemu-guest-agent reports an IP"
  value       = local.controlplanes_output
}

output "workers" {
  description = "Worker VMs formatted for cluster/talos (hostname, endpoint, node, config_patches). DHCP guests appear once qemu-guest-agent reports an IP"
  value       = local.workers_output
}
