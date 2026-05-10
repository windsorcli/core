output "machine_secrets" {
  description = "Full Talos cluster identity. cluster/talos consumes for per-node config templating; cluster/talos/config consumes to sign per-node configs before CIDATA wrapping."
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "client_configuration" {
  description = "Subset of secrets needed for the talosctl client (CA cert + admin cert/key). Used by cluster/talos's talos_client_configuration data source to generate the talosconfig file."
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}
