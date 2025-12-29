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
  description = "List of all instances with their details (name, ipv4, ipv6, status, type, image). IPv4 uses actual assigned IP if available, otherwise falls back to calculated/expected IP"
  value = [
    for k, v in module.instances : {
      name = v.name
      ipv4 = v.ipv4_address != null && v.ipv4_address != "" ? v.ipv4_address : (
        try(local.all_instances_by_name[k].ipv4 != null ? split("/", local.all_instances_by_name[k].ipv4)[0] : null, null)
      )
      ipv6   = v.ipv6_address
      status = v.status
      type   = v.type
      image  = v.image
    }
  ]
}
