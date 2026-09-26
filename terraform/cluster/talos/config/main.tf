# The before-compute Hyper-V stage: CIDATA seeds, optional machineconfig bake.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    hyperv = {
      source  = "windsorcli/hyperv"
      version = "0.4.0"
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
# back via terraform_output. Created whether or not the machineconfig is baked,
# so the identity survives a later cluster_endpoint change.
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

moved {
  from = talos_machine_secrets.this[0]
  to   = talos_machine_secrets.this
}

# =============================================================================
# Per-node Normalization
# =============================================================================

locals {
  # Empty cluster_endpoint skips the CIDATA machineconfig bake (DHCP), leaving
  # the apply to cluster/talos.
  bake_machineconfig = var.cluster_endpoint != ""
  dhcp               = var.network.dhcp == true

  network_prefix_length = var.network.cidr_block != null ? tonumber(split("/", var.network.cidr_block)[1]) : null

  controlplanes_normalized = [
    for n in var.controlplanes : {
      hostname = n.hostname
      node     = n.node
      address  = n.address != null ? n.address : (n.node != null && local.network_prefix_length != null ? "${n.node}/${local.network_prefix_length}" : null)
    }
  ]

  workers_normalized = [
    for n in var.workers : {
      hostname = n.hostname
      node     = n.node
      address  = n.address != null ? n.address : (n.node != null && local.network_prefix_length != null ? "${n.node}/${local.network_prefix_length}" : null)
    }
  ]

  dhcp_network_patch = yamlencode({
    machine = {
      network = merge(
        {
          interfaces = [{
            deviceSelector = { physical = true }
            dhcp           = true
          }]
        },
        length(coalesce(var.network.nameservers, [])) > 0 ? { nameservers = var.network.nameservers } : {}
      )
    }
  })

  controlplane_network_patches = {
    for n in local.controlplanes_normalized : n.hostname => (
      local.dhcp ? local.dhcp_network_patch : yamlencode({
        machine = {
          network = {
            interfaces = [{
              deviceSelector = { physical = true }
              dhcp           = false
              addresses      = [n.address]
              routes = [{
                network = "0.0.0.0/0"
                gateway = var.network.gateway
              }]
            }]
            nameservers = var.network.nameservers
          }
        }
      })
    )
  }

  worker_network_patches = {
    for n in local.workers_normalized : n.hostname => (
      local.dhcp ? local.dhcp_network_patch : yamlencode({
        machine = {
          network = {
            interfaces = [{
              deviceSelector = { physical = true }
              dhcp           = false
              addresses      = [n.address]
              routes = [{
                network = "0.0.0.0/0"
                gateway = var.network.gateway
              }]
            }]
            nameservers = var.network.nameservers
          }
        }
      })
    )
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
  for_each = local.bake_machineconfig ? { for n in local.controlplanes_normalized : n.hostname => n } : {}

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
  for_each = local.bake_machineconfig ? { for n in local.workers_normalized : n.hostname => n } : {}

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

  files = merge({
    "meta-data" = yamlencode({
      "instance-id"    = each.key
      "local-hostname" = each.key
    })
    # version: 2 must lead; yamlencode puts ethernets first and nocloud uses DHCP.
    "network-config" = local.dhcp ? format(
      "version: 2\nethernets:\n  primary:\n    match:\n      name: \"%s\"\n    dhcp4: true\n%s",
      var.network.interface,
      length(coalesce(var.network.nameservers, [])) > 0
      ? "    nameservers:\n      addresses:\n${join("\n", [for ns in var.network.nameservers : "        - ${ns}"])}\n"
      : ""
      ) : format(
      "version: 2\nethernets:\n  primary:\n    match:\n      name: \"%s\"\n    addresses:\n      - %s\n    gateway4: %s\n    nameservers:\n      addresses:\n%s\n",
      var.network.interface,
      each.value.address,
      var.network.gateway,
      join("\n", [for ns in coalesce(var.network.nameservers, []) : "        - ${ns}"])
    )
    }, local.bake_machineconfig ? {
    "user-data" = local.per_node_machineconfig[each.key]
  } : {})
}

# Land the synthesized bytes at destination_path on the host. literal_bytes
# mode (content_base64) decouples this from any local file on the runner.
resource "hyperv_image_file" "cidata" {
  for_each = local.nodes_by_hostname

  destination_path = "${var.destination_dir}/${each.key}${var.name_suffix}-cidata.iso"
  content_base64   = data.hyperv_iso_volume.cidata[each.key].content_base64

  # Hyper-V holds an exclusive handle on a mounted ISO; the VM lives in the
  # compute state, so Terraform cannot order these two on its own.
  replace_while_mounted = true
  force_destroy         = true
}
