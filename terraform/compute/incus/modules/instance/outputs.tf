#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------

output "name" {
  description = "The name of the Incus instance"
  value       = incus_instance.this.name
}

output "type" {
  description = "The type of the Incus instance"
  value       = incus_instance.this.type
}

output "ipv4_address" {
  description = "The primary IPv4 address of the instance"
  value       = try(incus_instance.this.ipv4_address, null)
}

output "ipv6_address" {
  description = "The primary IPv6 address of the instance"
  value       = try(incus_instance.this.ipv6_address, null)
}

output "image" {
  description = "The image fingerprint used for the instance"
  value       = incus_instance.this.image
}

output "status" {
  description = "The status of the instance"
  value       = incus_instance.this.status
}

