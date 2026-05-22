# -----------------------------------------------------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------------------------------------------------

output "cidata_isos" {
  description = "Per-node CIDATA ISO paths on the host. Keyed by hostname; values feed into compute/hyperv's instances[].cidata_iso_path so each VM gets the matching seed mounted as a second DVD."
  value       = { for k, r in hyperv_image_file.cidata : k => r.destination_path }
}

output "cidata_iso_shas" {
  description = "Per-node CIDATA ISO SHA-256 hashes (lowercase hex, host-on-disk values). Useful for cross-checking the on-host bytes match the runner-built bytes."
  value       = { for k, r in hyperv_image_file.cidata : k => r.sha256 }
}

output "machine_secrets" {
  description = "Talos cluster identity. Pass to cluster/talos as var.machine_secrets so it shares the same cluster CA — cluster/talos then skips talos_machine_configuration_apply (already delivered via CIDATA) and runs straight to bootstrap + kubeconfig + health checks."
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration (CA cert + admin cert/key). Pass to cluster/talos as var.client_configuration so its talos_client_configuration data source can generate a working talosconfig file."
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}

output "controlplanes" {
  description = "Pass-through of the controlplanes input, normalized with the resolved per-node address."
  value       = local.controlplanes_normalized
}

output "workers" {
  description = "Pass-through of the workers input, normalized with the resolved per-node address."
  value       = local.workers_normalized
}
