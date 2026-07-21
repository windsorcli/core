locals {
  # Talos-shaped node records. endpoint is the Talos API (port 50000) on the
  # public IP; node is the public IP cluster/talos applies config to.
  controlplanes = [
    for k, v in local.controlplane_nodes : {
      hostname     = v.hostname
      endpoint     = "${hcloud_server.this[k].ipv4_address}:50000"
      node         = hcloud_server.this[k].ipv4_address
      name         = hcloud_server.this[k].name
      ipv4         = hcloud_server.this[k].ipv4_address
      ipv6         = hcloud_server.this[k].ipv6_address
      private_ipv4 = local.private_ips[k]
      server_type  = v.server_type
    }
  ]

  workers = [
    for k, v in local.worker_nodes : {
      hostname     = v.hostname
      endpoint     = "${hcloud_server.this[k].ipv4_address}:50000"
      node         = hcloud_server.this[k].ipv4_address
      name         = hcloud_server.this[k].name
      ipv4         = hcloud_server.this[k].ipv4_address
      ipv6         = hcloud_server.this[k].ipv6_address
      private_ipv4 = local.private_ips[k]
      server_type  = v.server_type
    }
  ]
}

#---------------------------------------------------------------------------------------------------
# Outputs
#---------------------------------------------------------------------------------------------------

output "controlplanes" {
  description = "Control plane nodes formatted for Talos (hostname, endpoint, node, private_ipv4). Empty until IPs are assigned."
  value       = local.controlplanes
}

output "workers" {
  description = "Worker nodes formatted for Talos (hostname, endpoint, node, private_ipv4). Empty when no workers exist."
  value       = local.workers
}

output "network_id" {
  description = "Id of the private network, consumed by the hcloud cloud-controller-manager for pod routing."
  value       = hcloud_network.this.id
}

output "network_name" {
  description = "Name of the private network."
  value       = hcloud_network.this.name
}

output "node_subnet_cidr" {
  description = "The /24 subnet nodes are attached to within the private network."
  value       = local.node_subnet_cidr
}

output "location" {
  description = "Hetzner location the servers run in; consumed by the cloud load balancer."
  value       = var.location
}

output "network_zone" {
  description = "Hetzner network zone the private network spans."
  value       = var.network_zone
}
