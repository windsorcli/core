output "machine_configuration" {
  value = module.controlplanes[0].machine_configuration
  sensitive = true
}
