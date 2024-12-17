output "machine_configuration" {
  value = data.talos_machine_configuration.this.machine_configuration
  sensitive = true
}
