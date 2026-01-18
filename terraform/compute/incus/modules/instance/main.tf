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
  # Determine wait behavior for network addresses
  # - IPv4: wait if static IPv4 is set, or if wait_for_ipv4 is true (DHCP case, default true)
  # - IPv6: wait if static IPv6 is set, or if wait_for_ipv6 is explicitly true (DHCP case, default false)
  # - This allows fine-grained control: IPv4-only, IPv6-only, or both
  wait_for_ipv4 = var.ipv4 != null || var.wait_for_ipv4
  wait_for_ipv6 = var.ipv6 != null || (var.wait_for_ipv6 != null && var.wait_for_ipv6)

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
          # Add static IPv4/IPv6 if specified
          # Device ipv4.address/ipv6.address expects IP only, not CIDR notation
          # Only apply to primary interface (eth0)
          # security.ipv4_filtering prevents ARP spoofing but blocks LoadBalancer VIPs (kube-vip, MetalLB)
          merge(
            var.ipv4 != null && idx == 0 ? {
              "ipv4.address"            = split("/", var.ipv4)[0]
              "security.ipv4_filtering" = tostring(var.ipv4_filtering_enabled)
            } : {},
            var.ipv6 != null && idx == 0 ? {
              "ipv6.address" = split("/", var.ipv6)[0]
            } : {}
          )
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
          # Add static IPv4/IPv6 if specified
          # Device ipv4.address/ipv6.address expects IP only, not CIDR notation
          # security.ipv4_filtering prevents ARP spoofing but blocks LoadBalancer VIPs (kube-vip, MetalLB)
          merge(
            var.ipv4 != null ? {
              "ipv4.address"            = split("/", var.ipv4)[0]
              "security.ipv4_filtering" = tostring(var.ipv4_filtering_enabled)
            } : {},
            var.ipv6 != null ? {
              "ipv6.address" = split("/", var.ipv6)[0]
            } : {}
          )
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

  # Wait for network addresses on primary interface (eth0)
  # - IPv4: waits if static IPv4 is set, or if wait_for_network is true (DHCP)
  # - IPv6: waits if static IPv6 is set, or if wait_for_ipv6 is explicitly true (DHCP)
  # - Allows scenarios: IPv4-only DHCP, IPv6-only DHCP, both, or neither
  # - For multi-homed instances, eth0 is always the primary interface where static IPs are assigned
  # Note: eth0 is stable in Incus - it's always the first interface (eth0, eth1, etc. for multi-homed)
  dynamic "wait_for" {
    for_each = local.wait_for_ipv4 ? [1] : []
    content {
      type = "ipv4"
      nic  = "eth0"
    }
  }

  dynamic "wait_for" {
    for_each = local.wait_for_ipv6 ? [1] : []
    content {
      type = "ipv6"
      nic  = "eth0"
    }
  }

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

