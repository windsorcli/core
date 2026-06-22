# -----------------------------------------------------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------------------------------------------------

output "network_name" {
  description = "Port group name the VMs are attached to"
  value       = var.network
}

output "instances" {
  description = "Flat list of all VMs. Generic shape (name, hostname, ipv4, ipv6, status, type, image, role) matching compute/hyperv and compute/incus"
  value       = local.instances_output
}

output "controlplanes" {
  description = "Controlplane VMs formatted for cluster/talos (hostname, endpoint, node). Populated once vmtoolsd reports a guest IP to vCenter"
  value       = local.controlplanes_output
}

output "workers" {
  description = "Worker VMs formatted for cluster/talos (hostname, endpoint, node). Populated once vmtoolsd reports a guest IP to vCenter"
  value       = local.workers_output
}

output "machine_secrets" {
  description = "Talos cluster identity (CA, etcd CA, k8s CA, bootstrap token). Pass to cluster/talos as var.machine_secrets so it shares the same cluster CA — cluster/talos then skips talos_machine_configuration_apply (already delivered via guestinfo) and runs straight to bootstrap + kubeconfig + health checks"
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration (CA cert + admin cert/key). Pass to cluster/talos as var.client_configuration so its talos_client_configuration data source can generate a working talosconfig file"
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}
