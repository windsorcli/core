# The hcloud compute module provisions Talos Linux nodes on Hetzner Cloud.
# It builds a Talos Image Factory snapshot (via the imager provider), creates a
# private network, and boots servers from the snapshot into Talos maintenance
# mode. Windsor's cluster/talos module then applies machine config over each
# server's public IP. Outputs match the compute contract (controlplanes/workers
# with node/endpoint) consumed by cluster/talos.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.66.1"
    }
    imager = {
      source  = "hcloud-talos/imager"
      version = "1.0.16"
    }
  }
}

# token comes from var.hcloud_token (sourced from the sensitive hetzner.token
# config); an empty value falls back to the HCLOUD_TOKEN environment variable so
# the module still runs standalone in tests.
provider "hcloud" {
  token = var.hcloud_token != "" ? var.hcloud_token : null
}

provider "imager" {
  token = var.hcloud_token != "" ? var.hcloud_token : null
}

# =============================================================================
# Instance Expansion
# =============================================================================

locals {
  # Expand each group's count into 1-indexed nodes keyed by "<name>-<n>".
  nodes = merge([
    for group in var.instances : {
      for n in range(1, group.count + 1) :
      "${group.name}-${n}" => {
        hostname     = "${group.name}-${n}"
        role         = group.role
        server_type  = group.server_type
        architecture = startswith(lower(group.server_type), "cax") ? "arm" : "x86"
        index        = n
      }
    }
  ]...)

  controlplane_nodes = { for k, v in local.nodes : k => v if v.role == "controlplane" }
  worker_nodes       = { for k, v in local.nodes : k => v if v.role == "worker" }

  # Deterministic private IPs: control planes from .10, workers from .20.
  private_ips = merge(
    { for k, v in local.controlplane_nodes : k => cidrhost(local.node_subnet_cidr, 9 + v.index) },
    { for k, v in local.worker_nodes : k => cidrhost(local.node_subnet_cidr, 19 + v.index) },
  )

  architectures = distinct([for k, v in local.nodes : v.architecture])
}

# =============================================================================
# Network Resources
# =============================================================================

# Carve a /24 node subnet from the private network. A network already /24 or
# smaller is used whole.
locals {
  network_prefix = tonumber(split("/", var.network_cidr)[1])
  # Netnum 0 keeps the node subnet aligned to the network base, so private IPs
  # land at cidrhost(network_cidr, N) — the offset the platform facet reuses for
  # a stable Cilium k8sServiceHost (control plane at .10).
  node_subnet_cidr = local.network_prefix >= 24 ? var.network_cidr : cidrsubnet(var.network_cidr, 24 - local.network_prefix, 0)
  network_name     = "network-${var.context_id}"
}

resource "hcloud_network" "this" {
  name     = local.network_name
  ip_range = var.network_cidr
  labels   = local.labels
}

resource "hcloud_network_subnet" "this" {
  network_id   = hcloud_network.this.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = local.node_subnet_cidr
}

# =============================================================================
# Security Resources
# =============================================================================

# Stateful public-interface firewall. Private-network traffic is unfiltered by
# hcloud firewalls, so node-to-node needs no rules here.
resource "hcloud_firewall" "this" {
  name   = "firewall-${var.context_id}"
  labels = local.labels

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50000"
    source_ips = var.api_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = var.api_allowed_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# =============================================================================
# Talos Image
# =============================================================================

# Build one snapshot per architecture in use, unless a pre-existing snapshot id
# is supplied for that architecture. The temporary upload server runs in the
# cluster location using a node server type of the same architecture — that
# (location, server_type) pair is guaranteed orderable since the cluster itself
# uses it, avoiding location-specific availability gaps. Snapshots are
# project-global, so location choice doesn't limit where nodes can later run.
resource "imager_image" "this" {
  for_each = { for arch in local.architectures : arch => arch if lookup(var.image_ids, arch, "") == "" }

  image_url    = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/hcloud-${each.value == "arm" ? "arm64" : "amd64"}.raw.xz"
  architecture = each.value
  location     = var.location
  server_type  = local.build_server_type[each.value]
  description  = "talos-v${var.talos_version}-${each.value}-${var.context_id}"
  labels       = local.labels
}

locals {
  # First node server type per architecture, reused for that architecture's
  # snapshot-build server so it's known-orderable in var.location.
  build_server_type = {
    for arch in local.architectures : arch => [
      for k, v in local.nodes : v.server_type if v.architecture == arch
    ][0]
  }
}

locals {
  labels = merge(var.labels, {
    "windsorcli.dev/context-id" = var.context_id
    "windsorcli.dev/managed-by" = "windsor"
  })

  # Resolve each architecture to a snapshot id: supplied id wins, else the built one.
  image_id_by_arch = {
    for arch in local.architectures : arch => (
      lookup(var.image_ids, arch, "") != "" ? var.image_ids[arch] : imager_image.this[arch].id
    )
  }
}

# =============================================================================
# Compute Resources
# =============================================================================

# Spread placement keeps control planes on distinct physical hosts for HA.
resource "hcloud_placement_group" "this" {
  name   = "placement-${var.context_id}"
  type   = "spread"
  labels = local.labels
}

# Force replacement instead of in-place resize when a worker's server_type
# changes: an in-place hcloud resize reboots the node and can corrupt the
# container image store. Control planes are excluded — destroying one can lose
# etcd/cluster state — so they resize in place. Image changes are never a
# trigger (Talos version upgrades run in place via talosctl).
resource "terraform_data" "node_replacement" {
  for_each = local.nodes
  # Constant for control planes (never force-replaced); server_type for workers.
  triggers_replace = each.value.role == "controlplane" ? "protected" : each.value.server_type
}

resource "hcloud_server" "this" {
  for_each = local.nodes

  name               = "${each.value.hostname}-${var.context_id}"
  server_type        = each.value.server_type
  image              = local.image_id_by_arch[each.value.architecture]
  location           = var.location
  placement_group_id = hcloud_placement_group.this.id
  firewall_ids       = [hcloud_firewall.this.id]

  labels = merge(local.labels, {
    role     = each.value.role
    hostname = each.value.hostname
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # Servers boot the Talos snapshot into maintenance mode; cluster/talos applies
  # config over the network, so no user_data config is delivered here.
  depends_on = [hcloud_network_subnet.this]

  lifecycle {
    replace_triggered_by = [terraform_data.node_replacement[each.key]]
  }
}

resource "hcloud_server_network" "this" {
  for_each = local.nodes

  server_id  = hcloud_server.this[each.key].id
  network_id = hcloud_network.this.id
  ip         = local.private_ips[each.key]
}
