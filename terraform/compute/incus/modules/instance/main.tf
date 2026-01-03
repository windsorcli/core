#-----------------------------------------------------------------------------------------------------------------------
# Providers
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0.2"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Instance Resource
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # Build device map for this instance, including network devices
  instance_devices = merge(
    var.devices,
    length(var.networks) > 0 ? {
      for idx, network_name in var.networks : "eth${idx}" => {
        type = "nic"
        properties = merge(
          {
            network = network_name
          },
          var.network_config,
          # Add static IPv4 if specified (requires security.ipv4_filtering when DHCP is disabled)
          # Device ipv4.address expects IP only, not CIDR notation
          # Only apply IPv4 to primary interface (eth0)
          var.ipv4 != null && idx == 0 ? {
            "ipv4.address"            = split("/", var.ipv4)[0] # Extract IP address only (remove /prefix)
            "security.ipv4_filtering" = "true"                  # Required to allow static IP when DHCP is disabled
          } : {}
        )
      }
      } : {
      "eth0" = {
        type = "nic"
        properties = merge(
          {
            network = var.network_name
          },
          var.network_config,
          # Add static IPv4 if specified (requires security.ipv4_filtering when DHCP is disabled)
          # Device ipv4.address expects IP only, not CIDR notation
          var.ipv4 != null ? {
            "ipv4.address"            = split("/", var.ipv4)[0] # Extract IP address only (remove /prefix)
            "security.ipv4_filtering" = "true"                  # Required to allow static IP when DHCP is disabled
          } : {}
        )
      }
    },
    # Add root disk for all instances (containers and VMs need it)
    {
      "root" = {
        type = "disk"
        properties = merge(
          {
            path = "/"
            pool = "default"
          },
          # VM-specific root disk properties
          var.type == "virtual-machine" ? {
            # Set high boot priority for root disk (boots before network)
            "boot.priority" = "10"
          } : {},
          # Root disk size (only applies to VMs, ignored for containers)
          var.type == "virtual-machine" && var.root_disk_size != null ? {
            "size" = var.root_disk_size
          } : {}
        )
      }
    },
    # Add additional disk devices (if configured)
    length(var.disks) > 0 ? {
      for disk in var.disks : disk.name => {
        type = "disk"
        properties = merge(
          # Detect file path bind mounts vs storage volumes:
          # - File paths: start with "/" (Unix), "C:"/"D:" etc (Windows drive), or "\\" (UNC)
          # - Storage volumes: simple names without path separators
          # If source is not provided, we're creating a new volume (include pool, size required)
          disk.source != null && disk.source != "" && (
            length(regexall("^/", disk.source)) > 0 ||         # Unix absolute path
            length(regexall("^[A-Za-z]:", disk.source)) > 0 || # Windows drive letter (C:, D:, etc.)
            length(regexall("^\\\\", disk.source)) > 0         # Windows UNC path (\\server\share)
            ) ? {
            # File path bind mount - source is the host path, no pool needed
            source = disk.source
            } : {
            # Storage volume - include pool, source is volume name (or empty if creating new volume)
            pool   = disk.pool
            source = disk.source
          },
          disk.size != null ? {
            size = disk.size
          } : {},
          disk.path != null ? {
            path = disk.path
          } : {},
          disk.read_only ? {
            readonly = "true"
          } : {}
        )
      }
    } : {},
    # Add proxy devices for port forwarding (if configured)
    length(var.proxy_devices) > 0 ? {
      for proxy_name, proxy_config in var.proxy_devices : proxy_name => {
        type = "proxy"
        properties = {
          listen  = proxy_config.listen
          connect = proxy_config.connect
        }
      }
    } : {}
  )
}

resource "incus_instance" "this" {
  name        = var.name
  description = var.description
  type        = var.type
  image       = var.image
  project     = var.project
  remote      = var.remote
  target      = var.target
  ephemeral   = var.ephemeral

  dynamic "device" {
    for_each = local.instance_devices
    content {
      name       = device.key
      type       = device.value.type
      properties = device.value.properties
    }
  }

  config = merge(
    var.limits != null ? {
      "limits.cpu"    = var.limits.cpu
      "limits.memory" = var.limits.memory
    } : {},
    # VM-specific configuration
    var.type == "virtual-machine" ? merge(
      {
        "security.secureboot" = tostring(var.secureboot)
      },
      var.qemu_args != "" ? {
        "raw.qemu" = var.qemu_args
      } : {}
    ) : {},
    # User config merged last (can override defaults)
    var.config
  )

  profiles = var.profiles
}

