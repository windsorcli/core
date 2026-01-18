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

output "ipv4" {
  description = "The primary IPv4 address of the instance. Falls back to input ipv4 if instance address is not yet available"
  value       = incus_instance.this.ipv4_address != null ? incus_instance.this.ipv4_address : (var.ipv4 != null ? split("/", var.ipv4)[0] : null)
}

output "ipv6" {
  description = "The primary IPv6 address of the instance. Falls back to input ipv6 if instance address is not yet available"
  value       = incus_instance.this.ipv6_address != null ? incus_instance.this.ipv6_address : (var.ipv6 != null ? split("/", var.ipv6)[0] : null)
}

output "image" {
  description = "The image fingerprint used for the instance"
  value       = incus_instance.this.image
}

output "status" {
  description = "The status of the instance"
  value       = incus_instance.this.status
}

