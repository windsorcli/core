# The Talos Config module is the "before-compute" stage on hyperv (and any
# future hypervisor without a metadata service or DHCP). It owns three jobs:
#
#   1. Generate the cluster identity (talos_machine_secrets).
#   2. Sign per-node machineconfigs against that identity.
#   3. Wrap each per-node config (plus a cloud-init network-config bringing up
#      the VM's static IP) into a CIDATA seed ISO via hyperv_iso_volume.
#
# compute/hyperv attaches each ISO as the matching VM's second DVD; Talos
# boots with `talos.platform=nocloud` (kernel cmdline override baked into the
# Image Factory schematic), discovers the CIDATA volume, applies the
# machineconfig (including static network), and comes up at the configured
# IP with the cluster identity already installed.
#
# The same cluster identity is exported back to cluster/talos via outputs:
# its talosctl bootstrap + kubeconfig + health-check flow runs against the
# now-reachable nodes without a redundant talos_machine_configuration_apply
# (cluster/talos's apply step is gated off when machine_secrets is supplied).
#
# Dependency chain in a hyperv blueprint:
#   talos/config (this module)  →  compute (consumes cidata_isos)
#   talos/config (this module)  →  cluster (consumes machine_secrets +
#                                            client_configuration)

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    hyperv = {
      source  = "windsorcli/hyperv"
      version = "0.3.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}

# =============================================================================
# Cluster Identity
# =============================================================================

# Talos cluster identity (CA, etcd CA, k8s CA, bootstrap token, encryption
# secret). cluster/talos has its own count-gated copy of the same resource for
# the non-hyperv path; on hyperv this one is the producer and its outputs flow
# back via terraform_output. Inlined directly rather than wrapped in a submodule
# because the wrapper is one resource and the indirection makes state-address
# migrations (e.g. adding a count gate) needlessly painful.
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

# =============================================================================
# Per-node Normalization
# =============================================================================

locals {
  network_prefix_length = tonumber(split("/", var.network.cidr_block)[1])

  # Address resolution: caller may supply a per-node CIDR address, otherwise
  # we derive from node + var.network.cidr_block's prefix.
  controlplanes_normalized = [
    for n in var.controlplanes : {
      hostname = n.hostname
      node     = n.node
      address  = n.address != null ? n.address : "${n.node}/${local.network_prefix_length}"
    }
  ]

  workers_normalized = [
    for n in var.workers : {
      hostname = n.hostname
      node     = n.node
      address  = n.address != null ? n.address : "${n.node}/${local.network_prefix_length}"
    }
  ]

  # Per-node static-network patch. Talos honors machine.network.interfaces[]
  # from the machineconfig (applied by the nocloud platform after CIDATA read),
  # so static IP setup happens before the maintenance service comes up. The
  # interfaceless `interface` field name comes from Talos's machineconfig
  # schema (deviceSelector or interface; we use interface for a plain
  # "match by name" rule).
  controlplane_network_patches = {
    for n in local.controlplanes_normalized : n.hostname => yamlencode({
      # Talos 1.12+ auto-derives machine.network.hostname from the runtime
      # (Hyper-V VM hostname, CIDATA meta-data local-hostname, DHCP, etc.)
      # and REJECTS an explicit override with "static hostname is already
      # set in v1alpha1 config". The hostname comes from CIDATA's meta-data
      # file (local-hostname = <hostname>) instead.
      machine = {
        network = {
          # deviceSelector { physical: true } matches by hardware property
          # rather than by name — `interface: eth0` is fragile because
          # systemd-udev names Hyper-V synthetic NICs as `enX0` on modern
          # Talos, and a name mismatch causes Talos to silently skip the
          # static config and fall back to platform-level DHCP. Single-NIC
          # VMs (the common case here) match exactly one device this way.
          # dhcp: false is REQUIRED to suppress DHCP even when addresses
          # are set — empirically observed: without it, DHCP-leased
          # addresses win over the static config.
          interfaces = [{
            deviceSelector = {
              physical = true
            }
            dhcp      = false
            addresses = [n.address]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.network.gateway
            }]
          }]
          nameservers = var.network.nameservers
        }
      }
    })
  }

  worker_network_patches = {
    for n in local.workers_normalized : n.hostname => yamlencode({
      # Talos 1.12+ auto-derives machine.network.hostname from the runtime
      # (Hyper-V VM hostname, CIDATA meta-data local-hostname, DHCP, etc.)
      # and REJECTS an explicit override with "static hostname is already
      # set in v1alpha1 config". The hostname comes from CIDATA's meta-data
      # file (local-hostname = <hostname>) instead.
      machine = {
        network = {
          # deviceSelector { physical: true } matches by hardware property
          # rather than by name — `interface: eth0` is fragile because
          # systemd-udev names Hyper-V synthetic NICs as `enX0` on modern
          # Talos, and a name mismatch causes Talos to silently skip the
          # static config and fall back to platform-level DHCP. Single-NIC
          # VMs (the common case here) match exactly one device this way.
          # dhcp: false is REQUIRED to suppress DHCP even when addresses
          # are set — empirically observed: without it, DHCP-leased
          # addresses win over the static config.
          interfaces = [{
            deviceSelector = {
              physical = true
            }
            dhcp      = false
            addresses = [n.address]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.network.gateway
            }]
          }]
          nameservers = var.network.nameservers
        }
      }
    })
  }
}

# =============================================================================
# Per-node Machine Configurations
# =============================================================================

# data.talos_machine_configuration generates a Talos machineconfig for each
# node, signed against talos_machine_secrets.this's cluster identity. The
# output is a YAML string containing the cluster CA, node identity, kubelet
# config, and any patches we've layered in. CIDATA wraps it as user-data.
data "talos_machine_configuration" "controlplane" {
  for_each = { for n in local.controlplanes_normalized : n.hostname => n }

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    var.common_config_patches,
    var.controlplane_config_patches,
    local.controlplane_network_patches[each.key],
  ])
}

data "talos_machine_configuration" "worker" {
  for_each = { for n in local.workers_normalized : n.hostname => n }

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    var.common_config_patches,
    var.worker_config_patches,
    local.worker_network_patches[each.key],
  ])
}

locals {
  per_node_machineconfig = merge(
    { for k, v in data.talos_machine_configuration.controlplane : k => v.machine_configuration },
    { for k, v in data.talos_machine_configuration.worker : k => v.machine_configuration },
  )

  nodes_by_hostname = merge(
    { for n in local.controlplanes_normalized : n.hostname => n },
    { for n in local.workers_normalized : n.hostname => n },
  )
}

# =============================================================================
# CIDATA Build — per-node seed ISOs (full machineconfig + network-config)
# =============================================================================

# Two-step: synthesize the ISO9660 bytes via the data source (pure runner,
# no Hyper-V interaction), then land them on the host via hyperv_image_file
# in literal_bytes mode. The split mirrors the provider's separation of
# concerns — synthesis is a filesystem-image operation, placement is the
# Hyper-V concern. Same volume_label + same files yields byte-identical
# bytes via the data source's determinism contract, so the image_file
# resource only re-lands when content actually changes.
#
# CIDATA contents: meta-data (instance-id + hostname), user-data (the
# signed Talos machineconfig — Talos's nocloud platform reads this and
# applies it before maintenance mode comes up), and network-config
# (cloud-init v2, version: 2 at the top so cloud-init's parser doesn't
# fall back to DHCP).
data "hyperv_iso_volume" "cidata" {
  for_each = local.nodes_by_hostname

  volume_label = "CIDATA"

  files = {
    "meta-data" = yamlencode({
      "instance-id"    = each.key
      "local-hostname" = each.key
    })

    # Hand-formatted: version: 2 must be at the top of the file. yamlencode
    # emits keys alphabetically (ethernets first, version last); empirically
    # that order causes cloud-init / Talos's nocloud parser to fall back to
    # DHCP. Unquoted keys match every cloud-init reference doc.
    # match.name binds by NIC-name glob (default e*) so the static IP applies
    # whether the synthetic NIC comes up as eth0 or enX0.
    "network-config" = format(
      "version: 2\nethernets:\n  primary:\n    match:\n      name: \"%s\"\n    addresses:\n      - %s\n    gateway4: %s\n    nameservers:\n      addresses:\n%s\n",
      var.network.interface,
      each.value.address,
      var.network.gateway,
      join("\n", [for ns in var.network.nameservers : "        - ${ns}"])
    )

    # Full Talos machineconfig — signed against talos_machine_secrets, includes
    # static network in machine.network.interfaces. Talos's nocloud platform
    # treats user-data as the machineconfig (NOT cloud-init), so this is
    # what brings the node up to "running" with the configured identity.
    "user-data" = local.per_node_machineconfig[each.key]
  }
}

# Land the synthesized bytes at destination_path on the host. literal_bytes
# mode (content_base64) decouples this from any local file on the runner.
resource "hyperv_image_file" "cidata" {
  for_each = local.nodes_by_hostname

  destination_path = "${var.destination_dir}/${each.key}-cidata.iso"
  content_base64   = data.hyperv_iso_volume.cidata[each.key].content_base64
}
