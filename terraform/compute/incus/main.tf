# The Incus Compute module is a Terraform module for creating and managing Incus networks and instances
# It provides a generic interface for provisioning containers and virtual machines on Incus
# This module supports network creation, instance provisioning with configurable resources, and network attachment

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">=1.8"
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure Incus provider with remotes for image pulls
provider "incus" {
  remote {
    name     = "ghcr"
    address  = "https://ghcr.io"
    protocol = "oci"
    public   = true
  }
  remote {
    name     = "windsor"
    address  = "https://images.windsorcli.dev"
    protocol = "simplestreams"
    public   = true
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  network_name = var.network_name != "" ? var.network_name : "net-${var.context_id}"

  # Build network config: enable DHCP and NAT by default (configurable)
  # Static IPs on device ipv4.address act as static DHCP leases when DHCP is enabled
  network_config = merge(
    var.network_config != null ? var.network_config : {},
    var.network_cidr != null ? {
      "ipv4.address" = "${cidrhost(var.network_cidr, 1)}/${split("/", var.network_cidr)[1]}"
    } : {},
    {
      "ipv4.dhcp" = tostring(var.enable_dhcp)
      "ipv4.nat"  = tostring(var.enable_nat)
    }
  )

  # Extract network base IP and prefix length from CIDR for sequential IP calculation
  network_base_ip       = var.network_cidr != null ? cidrhost(var.network_cidr, 0) : null
  network_prefix_length = var.network_cidr != null ? tonumber(split("/", var.network_cidr)[1]) : null
}

# =============================================================================
# Network Resources
# =============================================================================

# Create network only if create_network is true
resource "incus_network" "main" {
  count = var.create_network ? 1 : 0

  name        = local.network_name
  description = var.network_description
  type        = var.network_type
  project     = var.project
  target      = var.network_target
  config      = local.network_config
}

# =============================================================================
# Image Resources
# =============================================================================

# Import local files via incus_image resource - returns fingerprint
resource "incus_image" "local" {
  for_each = local.image_local_files

  project = var.project
  remote  = var.remote != null && var.remote != "" ? var.remote : "local"

  source_file = {
    data_path = each.value
  }
}

# =============================================================================
# Storage Volume Resources
# =============================================================================

locals {
  # Collect all disks that need volumes created (have size but no source)
  # Expand instances first to handle count > 1
  expanded_instances_for_volumes = flatten([
    for instance in var.instances : [
      for i in range(lookup(instance, "count", 1)) : {
        instance_name = instance.count > 1 ? "${instance.name}-${i}" : instance.name
        disks         = lookup(instance, "disks", [])
      }
    ]
  ])

  # Transform disks from generic schema format (size as integer GB, type for pool) to Incus format
  expanded_instances_with_transformed_disks = [
    for expanded in local.expanded_instances_for_volumes : merge(
      expanded,
      {
        disks = [
          for disk in expanded.disks : {
            name      = disk.name
            pool      = lookup(disk, "type", "default") # Map type to pool for Incus
            size      = "${disk.size}GB"                # Convert integer GB to string with "GB" suffix
            source    = lookup(disk, "source", null)
            path      = lookup(disk, "path", null)
            read_only = lookup(disk, "read_only", false)
          }
        ]
      }
    )
  ]

  disks_needing_volumes = flatten([
    for expanded in local.expanded_instances_with_transformed_disks : [
      for disk in expanded.disks : {
        instance_name = expanded.instance_name
        disk_name     = disk.name
        pool          = disk.pool
        volume_name   = lookup(disk, "source", null) != null ? disk.source : "${expanded.instance_name}-${disk.name}"
        size          = disk.size
      }
      if lookup(disk, "size", null) != null && lookup(disk, "source", null) == null
    ]
  ])

  # Create unique volume keys
  volume_keys = {
    for disk in local.disks_needing_volumes : "${disk.instance_name}-${disk.disk_name}" => disk
  }
}

# Create storage volumes for disks that specify size
resource "incus_storage_volume" "disks" {
  for_each = local.volume_keys

  pool         = each.value.pool
  name         = each.value.volume_name
  type         = "custom"
  content_type = "block"

  config = {
    size = each.value.size
  }

  project = var.project
}

# =============================================================================
# Instance Resources
# =============================================================================

locals {
  # Calculate starting IP offset (skip gateway, typically .1)
  ip_start_offset = 2 # Start from .2 (assuming .1 is gateway)

  # Validate IP octet overflow before expansion
  # Check that instances with count > 1 and explicit ipv4 won't overflow the last octet
  ip_octet_overflow_instances = [
    for instance in var.instances : {
      name       = instance.name
      ipv4       = instance.ipv4
      count      = instance.count
      last_octet = instance.ipv4 != null ? tonumber(split(".", split("/", instance.ipv4)[0])[3]) : null
      max_octet  = instance.ipv4 != null && instance.count > 1 ? tonumber(split(".", split("/", instance.ipv4)[0])[3]) + (instance.count - 1) : null
    }
    if instance.ipv4 != null && instance.count > 1 && tonumber(split(".", split("/", instance.ipv4)[0])[3]) + (instance.count - 1) > 255
  ]

  # Expand instances: when count > 1, name becomes prefix with -0, -1, etc.
  expanded_instances = flatten([
    for instance in var.instances : [
      for i in range(instance.count) : {
        name           = instance.count > 1 ? "${instance.name}-${i}" : instance.name
        role           = lookup(instance, "role", null)
        image          = instance.image
        type           = instance.type
        description    = instance.count > 1 && instance.description != null ? "${instance.description} (${i + 1}/${instance.count})" : instance.description
        ephemeral      = instance.ephemeral
        target         = instance.target
        networks       = instance.networks
        network_config = instance.network_config
        ipv4 = instance.ipv4 != null && instance.count > 1 ? (
          # Increment from starting IP: extract last octet, add index, reconstruct
          # Use network_prefix_length from network_cidr if available, otherwise extract from instance IP
          format("%s/%s",
            join(".", [
              split(".", split("/", instance.ipv4)[0])[0],
              split(".", split("/", instance.ipv4)[0])[1],
              split(".", split("/", instance.ipv4)[0])[2],
              tostring(tonumber(split(".", split("/", instance.ipv4)[0])[3]) + i)
            ]),
            local.network_prefix_length != null ? tostring(local.network_prefix_length) : (
              length(split("/", instance.ipv4)) > 1 ? split("/", instance.ipv4)[1] : "24"
            )
          )
        ) : instance.ipv4
        ipv6           = lookup(instance, "ipv6", null)
        wait_for_ipv4  = lookup(instance, "wait_for_ipv4", true)
        wait_for_ipv6  = lookup(instance, "wait_for_ipv6", null)
        limits         = instance.limits
        profiles       = instance.profiles
        devices        = instance.devices
        proxy_devices  = instance.proxy_devices
        secureboot     = instance.secureboot
        qemu_args      = instance.qemu_args
        root_disk_size = instance.root_disk_size
        disks          = instance.disks
        config         = instance.config
      }
    ]
  ])

  # Track all instance names for sequential IP assignment
  all_instance_keys = [for instance in local.expanded_instances : instance.name]

  # Calculate sequential IPs when network_cidr is provided and no explicit IP provided
  # These will be assigned as static DHCP leases
  instance_sequential_ips = {
    for idx, instance_key in local.all_instance_keys : instance_key => (
      local.network_base_ip != null ? (
        "${cidrhost(var.network_cidr, local.ip_start_offset + idx)}/${local.network_prefix_length}"
      ) : null
    )
  }

  # Merge transformed disks back into expanded instances
  # Transform disks from generic schema format (size as integer GB, type for pool) to Incus format (size as string, pool)
  expanded_instances_with_disks = [
    for instance in local.expanded_instances : merge(
      instance,
      {
        disks = [
          for disk in lookup(instance, "disks", []) : {
            name      = disk.name
            pool      = lookup(disk, "type", "default") # Map type to pool for Incus
            size      = "${disk.size}GB"                # Convert integer GB to string with "GB" suffix
            source    = lookup(disk, "source", null)
            path      = lookup(disk, "path", null)
            read_only = lookup(disk, "read_only", false)
          }
        ]
      }
    )
  ]

  # Resolve disk source names (use created volume names if size was specified)
  # Note: If ipv4 is not specified, DHCP will assign an available IP automatically
  all_instances = [
    for instance in local.expanded_instances_with_disks : merge(
      instance,
      {
        ipv4 = instance.ipv4, # Only use explicit IPs, let DHCP handle the rest
        disks = [
          for disk in instance.disks : merge(
            disk,
            {
              source = lookup(disk, "source", null) != null ? disk.source : (
                lookup(local.volume_keys, "${instance.name}-${disk.name}", null) != null ?
                local.volume_keys["${instance.name}-${disk.name}"].volume_name : null
              )
            }
          )
        ]
      }
    )
  ]

  # Collect local file paths from all instances (after expansion)
  # Detects both Unix (/path) and Windows (C:\path or C:/path) file paths
  # Only includes files that actually exist
  image_local_files = {
    for instance in local.all_instances : instance.image => instance.image
    if fileexists(instance.image)
  }

  # Map instance images: resolve local files to fingerprints, pass through others as-is
  # Local files (detected from instances): get fingerprints from incus_image resource
  # Remote images, fingerprints, or other refs: pass through as-is
  # Note: This may cause concurrent pull issues for remote images, but incus_image resource doesn't work for remotes
  instance_images = {
    for instance in local.all_instances : instance.name => (
      # If instance.image is a local file path (Unix or Windows), use fingerprint
      fileexists(instance.image)
      ? incus_image.local[instance.image].fingerprint
      # Otherwise pass through as-is (could be remote ref, fingerprint, or alias)
      : instance.image
    )
  }

  # Create a map of all_instances keyed by name for easy lookup in outputs
  all_instances_by_name = {
    for instance in local.all_instances : instance.name => instance
  }

  # Calculate all assigned IP addresses (extract IP from CIDR notation)
  # This includes IPs from count expansion (e.g., 10.5.0.1/24 with count=3 creates 10.5.0.1, 10.5.0.2, 10.5.0.3)
  assigned_ips = {
    for instance in local.all_instances : instance.name => (
      instance.ipv4 != null ? split("/", instance.ipv4)[0] : null
    )
  }

  # Group instances by IP address to find conflicts
  ip_to_instances = {
    for ip, names in {
      for name, ip_addr in local.assigned_ips : ip_addr => name...
      if ip_addr != null
    } : ip => names
  }

  # Find IP conflicts: IPs assigned to multiple instances
  ip_conflicts = {
    for ip, instances in local.ip_to_instances : ip => instances
    if length(instances) > 1
  }

}


# Validate IP address configurations before creating instances
# Use terraform_data with lifecycle preconditions to fail plan/apply on validation errors
resource "terraform_data" "ip_validation" {
  # Validate that IP address octet overflow doesn't occur when incrementing with count > 1
  # Prevents invalid IPs like 10.0.0.260 when base IP is 10.0.0.250 with count=10
  lifecycle {
    precondition {
      condition = length(local.ip_octet_overflow_instances) == 0
      error_message = <<-EOT
        IPv4 address octet overflow detected. The following instances would generate invalid IP addresses:
        ${join("\n", [
      for inst in local.ip_octet_overflow_instances : "  Instance '${inst.name}' with ipv4='${inst.ipv4}' and count=${inst.count} would overflow last octet (max would be ${inst.max_octet}, valid range is 0-255)"
])}
        
        This occurs when an instance with count > 1 and an explicit ipv4 address would increment the last octet beyond 255.
        For example, ipv4="10.0.0.250/24" with count=10 would try to create IPs up to 10.0.0.259, which is invalid.
        
        Solution: Ensure that (last_octet + count - 1) <= 255. For example:
        - ipv4="10.0.0.250/24" with count=6 is valid (250 + 5 = 255)
        - ipv4="10.0.0.250/24" with count=10 is invalid (250 + 9 = 259 > 255)
        EOT
}

# Validate that no IP addresses are assigned to multiple instances
# This prevents conflicts when count > 1 increments IPs (e.g., instance with ipv4="10.5.0.1/24" and count=3
# creates IPs 10.5.0.1, 10.5.0.2, 10.5.0.3, which could conflict with another instance using 10.5.0.2)
precondition {
  condition = length(local.ip_conflicts) == 0
  error_message = <<-EOT
        IPv4 address conflicts detected. The following IP addresses are assigned to multiple instances:
        ${join("\n", [
  for ip, instances in local.ip_conflicts : "  IP ${ip} is assigned to: ${join(", ", instances)}"
])}
        
        This can occur when:
        1. An instance with count > 1 and an explicit ipv4 increments IPs (e.g., ipv4="10.5.0.1/24" with count=3 creates 10.5.0.1, 10.5.0.2, 10.5.0.3)
        2. Another instance explicitly uses one of those incremented IPs
        
        Solution: Ensure all IP addresses are unique across all instances, accounting for count-based IP increments.
        EOT
}
}

# This resource doesn't actually do anything, it's just a vehicle for preconditions
input = md5(jsonencode(local.all_instances))
}

# Create instances using the instance sub-module
# Depends on validation resource to ensure IP conflicts are caught before instance creation
module "instances" {
  source   = "./modules/instance"
  for_each = { for idx, instance in local.all_instances : instance.name => instance }

  name        = each.value.name
  description = lookup(each.value, "description", null)
  type        = lookup(each.value, "type", "container")
  image       = local.instance_images[each.value.name]
  project     = var.project
  remote      = var.remote
  target      = lookup(each.value, "target", null)
  ephemeral   = lookup(each.value, "ephemeral", false)

  network_name   = local.network_name
  networks       = lookup(each.value, "networks", [])
  network_config = lookup(each.value, "network_config", {})
  ipv4           = lookup(each.value, "ipv4", null)
  ipv6           = lookup(each.value, "ipv6", null)
  wait_for_ipv4  = lookup(each.value, "wait_for_ipv4", true)
  wait_for_ipv6  = lookup(each.value, "wait_for_ipv6", null)

  limits        = lookup(each.value, "limits", null)
  profiles      = lookup(each.value, "profiles", [])
  devices       = lookup(each.value, "devices", {})
  disks         = lookup(each.value, "disks", [])
  proxy_devices = lookup(each.value, "proxy_devices", {})

  secureboot     = lookup(each.value, "secureboot", false)
  root_disk_size = lookup(each.value, "root_disk_size", null)
  qemu_args      = lookup(each.value, "qemu_args", "-boot order=c,menu=off")
  config         = lookup(each.value, "config", {})

  # Explicitly depend on validation, network (if creating), storage volumes, and local images to ensure proper creation order
  # Local files are created via incus_image resource and have fingerprints
  # Remote images are passed directly to instances (they pull on demand, may have concurrent pulls)
  # Network will be destroyed after all instances are destroyed
  depends_on = [terraform_data.ip_validation, incus_network.main, incus_storage_volume.disks, incus_image.local]
}
