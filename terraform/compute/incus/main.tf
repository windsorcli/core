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
  network_name = var.network_name != "" ? var.network_name : "network-${var.context_id}"

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

locals {
  # Create image manifest map keyed by alias (for resolving instance image aliases)
  images_map = {
    for img in var.images : img.alias => img
  }

  # Collect all local file paths from manifest (for creating incus_image resources)
  # Only create resources for local files that exist
  image_local_files = {
    for alias, img in local.images_map : img.source_file => img.source_file
    if lookup(img, "source_file", null) != null && fileexists(img.source_file)
  }
}

# Import local files via incus_image resource - returns fingerprint
resource "incus_image" "local" {
  for_each = local.image_local_files

  project = var.project
  remote  = var.remote != null ? var.remote : "local"

  source_file = {
    data_path = each.value
  }
}

# Note: incus_image resource with source_image doesn't work for remote images
# - OCI remotes require skopeo
# - Simplestreams remotes fail with "image not found" errors
# So we only use incus_image for local files, and pass remote refs directly to instances


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

  disks_needing_volumes = flatten([
    for expanded in local.expanded_instances_for_volumes : [
      for disk in expanded.disks : {
        instance_name = expanded.instance_name
        disk_name     = disk.name
        pool          = lookup(disk, "pool", "default")
        volume_name   = lookup(disk, "source", null) != null ? disk.source : "${expanded.instance_name}-${disk.name}"
        size          = lookup(disk, "size", null)
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

  # Expand instances: when count > 1, name becomes prefix with -0, -1, etc.
  expanded_instances = flatten([
    for instance in var.instances : [
      for i in range(instance.count) : {
        name           = instance.count > 1 ? "${instance.name}-${i}" : instance.name
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
        limits        = instance.limits
        profiles      = instance.profiles
        devices       = instance.devices
        proxy_devices = instance.proxy_devices
        secureboot    = instance.secureboot
        qemu_args     = instance.qemu_args
        disks         = instance.disks
        config        = instance.config
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

  # Add sequential IPs to instances that don't have explicit IPs
  # Also resolve disk source names (use created volume names if size was specified)
  all_instances = [
    for instance in local.expanded_instances : merge(
      instance,
      {
        ipv4 = instance.ipv4 != null ? instance.ipv4 : (
          local.instance_sequential_ips[instance.name]
        ),
        disks = [
          for disk in lookup(instance, "disks", []) : merge(
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

  # Map instance images: resolve aliases from manifest
  # Local files: get fingerprints from incus_image resource
  # Remote images: resolve alias to "remote:image" format - instances will pull on demand
  # Direct paths/refs: pass through as-is
  # Note: This may cause concurrent pull issues for remote images, but incus_image resource doesn't work for remotes
  instance_images = {
    for instance in local.all_instances : instance.name => (
      # If instance.image is an alias in manifest, resolve it
      contains(keys(local.images_map), instance.image)
      ? (
        # If manifest entry has source_file, it's a local file - use fingerprint
        lookup(local.images_map[instance.image], "source_file", null) != null && fileexists(local.images_map[instance.image].source_file)
        ? incus_image.local[local.images_map[instance.image].source_file].fingerprint
        # Otherwise it's a remote - build "remote:image" format
        : "${local.images_map[instance.image].remote}:${local.images_map[instance.image].image}"
      )
      # Not in manifest - pass through as-is (could be direct file path, remote ref, or fingerprint)
      : instance.image
    )
  }

  # Create a map of all_instances keyed by name for easy lookup in outputs
  all_instances_by_name = {
    for instance in local.all_instances : instance.name => instance
  }

}

# Create instances using the instance sub-module
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

  limits        = lookup(each.value, "limits", null)
  profiles      = lookup(each.value, "profiles", [])
  devices       = lookup(each.value, "devices", {})
  disks         = lookup(each.value, "disks", [])
  proxy_devices = lookup(each.value, "proxy_devices", {})

  secureboot     = lookup(each.value, "secureboot", false)
  root_disk_size = lookup(each.value, "root_disk_size", null)
  qemu_args      = lookup(each.value, "qemu_args", "-boot order=c,menu=off")
  config         = lookup(each.value, "config", {})

  # Explicitly depend on network (if creating), storage volumes, and local images to ensure proper creation order
  # Local files are created via incus_image resource and have fingerprints
  # Remote images are passed directly to instances (they pull on demand, may have concurrent pulls)
  # Network will be destroyed after all instances are destroyed
  depends_on = [incus_storage_volume.disks, incus_image.local]
}
