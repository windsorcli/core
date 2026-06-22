# The vSphere Compute module creates and manages virtual machines on a VMware
# vSphere cluster. It mirrors the input/output contract of compute/hyperv and
# compute/incus so cluster/talos consumes any of them transparently.
#
# Provider credentials are env-var driven:
#   VSPHERE_SERVER               — vCenter hostname or IP
#   VSPHERE_USER                 — vCenter username (e.g. administrator@vsphere.local)
#   VSPHERE_PASSWORD             — vCenter password
#   VSPHERE_ALLOW_UNVERIFIED_SSL — "true" to skip TLS verification (self-signed certs)
#
# The module supports two VM categories on the same vSphere cluster:
#
#   Talos cluster nodes (role = "controlplane" | "worker")
#     Deployed from an OVA in var.images (reference by key in instance.image).
#     Per-node machineconfig — including static network config — is delivered via
#     VMware GuestInfo at creation time (extra_config). Talos reads guestinfo on
#     the vmware platform before maintenance mode, applies the machineconfig, and
#     comes up at the configured IP. vmtoolsd reports the guest IP back to vCenter.
#
#   Non-cluster VMs (any other role, or no role)
#     Any image in var.images, or a blank disk when image is empty. No machineconfig
#     is generated or delivered. These VMs appear in the `instances` output but not
#     in `controlplanes` or `workers`.
#
# Machine secrets (CA, bootstrap token, etc.) are generated inline — there is no
# separate cluster/talos/config step. machine_secrets and client_configuration
# flow to cluster/talos so it shares the same CA without re-generating secrets.
#
# Dependency chain in a vSphere blueprint:
#   compute (this module)  →  cluster/talos (consumes machine_secrets +
#                                            client_configuration + node IPs)

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.10"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}

# Provider block is intentionally empty — all connection settings are read from
# VSPHERE_SERVER / VSPHERE_USER / VSPHERE_PASSWORD / VSPHERE_ALLOW_UNVERIFIED_SSL.
# allow_unverified_ssl lets operators set it via the schema's vsphere.allow_unverified_ssl
# field without touching env vars, while still honouring the env-var override.
provider "vsphere" {
  allow_unverified_ssl = var.allow_unverified_ssl
}

# =============================================================================
# Locals — context and inventory IDs
# =============================================================================

locals {
  context_effective = var.context_id != "" ? var.context_id : var.context

  # VM folder: use operator-supplied path (relative to the datacenter VM root),
  # or fall back to "windsor-<context>" so VMs are grouped by deployment.
  vm_folder = var.folder != "" ? var.folder : "windsor-${local.context_effective}"

  # Resource pool: operator may supply a path relative to the compute cluster.
  # When empty, use the cluster's root resource pool.
  resource_pool_id = var.resource_pool != "" ? (
    data.vsphere_resource_pool.named[0].id
  ) : data.vsphere_compute_cluster.this.resource_pool_id
}

# =============================================================================
# vSphere Inventory Data Sources
# =============================================================================

data "vsphere_datacenter" "this" {
  name = var.datacenter
}

data "vsphere_datastore" "this" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_compute_cluster" "this" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.this.id
}

# Named resource pool — only resolved when var.resource_pool is non-empty.
data "vsphere_resource_pool" "named" {
  count         = var.resource_pool != "" ? 1 : 0
  name          = "${var.cluster}/Resources/${var.resource_pool}"
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.this.id
}

# =============================================================================
# Cluster Identity (Talos Machine Secrets)
# =============================================================================
#
# Generated inline — no separate cluster/talos/config step on vSphere because
# guestinfo delivery sets machineconfig during VM creation (no pre-compute ISO
# staging required). Exported so cluster/talos shares the same cluster CA.

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

# =============================================================================
# Instance Expansion
# =============================================================================

locals {
  network_prefix_length = var.network_cidr != null ? tonumber(split("/", var.network_cidr)[1]) : 24

  expanded_instances = flatten([
    for instance in var.instances : [
      for i in range(instance.count) : {
        name           = instance.count > 1 ? "${instance.name}-${i + 1}" : instance.name
        role           = instance.role
        image          = instance.image
        cpu            = instance.cpu
        memory         = instance.memory
        root_disk_size = instance.root_disk_size
        ipv4 = instance.ipv4 != null && instance.count > 1 ? format("%s.%s",
          join(".", slice(split(".", split("/", instance.ipv4)[0]), 0, 3)),
          tostring(tonumber(split(".", split("/", instance.ipv4)[0])[3]) + i)
        ) : (instance.ipv4 != null ? split("/", instance.ipv4)[0] : null)
        vlan_id       = instance.vlan_id
        notes         = instance.notes
        desired_state = instance.desired_state
        index         = i
      }
    ]
  ])

  instances_by_name = { for inst in local.expanded_instances : inst.name => inst }

  # Resolve image key → OVA URL. Blank or absent image key means no OVF deploy.
  instance_image_urls = {
    for k, v in local.instances_by_name : k => (
      v.image != null && v.image != "" && contains(keys(var.images), v.image)
      ? var.images[v.image].url
      : null
    )
  }
}

# =============================================================================
# Per-node Machine Configurations (Talos nodes only)
# =============================================================================
#
# Only generated for controlplane and worker instances. Non-cluster VMs (custom
# roles or no role) are skipped — they receive no guestinfo config and are not
# included in the controlplanes/workers outputs.
#
# Static network config is baked into each node's machineconfig via a
# machine.network.interfaces patch. Talos applies this before maintenance mode,
# so the node comes up at its configured static IP without DHCP — critical on
# isolated plant networks where no DHCP server may be present.
#
# deviceSelector { physical: true } is used rather than interface name (e.g.
# "eth0") because vSphere synthetic NICs may surface as "ens192" or "ens160"
# depending on the VMX hardware version. Single-NIC VMs always match exactly one.

locals {
  node_network_patches = {
    for k, v in local.instances_by_name : k => yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = { physical = true }
            dhcp           = false
            addresses      = ["${v.ipv4}/${local.network_prefix_length}"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.network_gateway
            }]
          }]
          nameservers = var.network_nameservers
        }
      }
    })
    if v.ipv4 != null && var.network_gateway != null
    && contains(["controlplane", "worker"], coalesce(v.role, ""))
  }
}

data "talos_machine_configuration" "controlplane" {
  for_each = { for k, v in local.instances_by_name : k => v if v.role == "controlplane" }

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    var.common_config_patches,
    lookup(local.node_network_patches, each.key, null),
  ])
}

data "talos_machine_configuration" "worker" {
  for_each = { for k, v in local.instances_by_name : k => v if v.role == "worker" }

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    var.common_config_patches,
    lookup(local.node_network_patches, each.key, null),
  ])
}

locals {
  machineconfigs = merge(
    { for k, v in data.talos_machine_configuration.controlplane : k => v.machine_configuration },
    { for k, v in data.talos_machine_configuration.worker : k => v.machine_configuration },
  )
}

# =============================================================================
# VM Resources
# =============================================================================
#
# ovf_deploy is a dynamic block: it fires only when the instance declares an
# image key that resolves to a URL in var.images. Non-Talos VMs with no image
# (or an image referencing a non-OVA artifact) get a blank disk instead.
#
# extra_config delivers the Talos machineconfig only when the role is
# controlplane or worker. All other VMs get an empty extra_config map so the
# resource is valid without a machineconfig to encode.
#
# lifecycle.ignore_changes covers ovf_deploy (initial bootstrap only), guest_id,
# and firmware — the OVA sets all three and Terraform should not fight them on
# subsequent applies.

resource "vsphere_virtual_machine" "instances" {
  for_each = local.instances_by_name

  name             = each.value.name
  resource_pool_id = local.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id
  folder           = local.vm_folder

  num_cpus   = each.value.cpu
  memory     = each.value.memory * 1024
  annotation = each.value.notes

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = "vmxnet3"
    ovf_mapping  = "VM Network"
  }

  disk {
    label            = "disk0"
    size             = each.value.root_disk_size
    thin_provisioned = true
    eagerly_scrub    = false
  }

  # OVF deployment — only when this instance references a known image.
  dynamic "ovf_deploy" {
    for_each = local.instance_image_urls[each.key] != null ? [1] : []
    content {
      remote_ovf_url    = local.instance_image_urls[each.key]
      disk_provisioning = "thin"
      ovf_network_map = {
        "VM Network" = data.vsphere_network.this.id
      }
    }
  }

  # Machineconfig via VMware GuestInfo — Talos cluster nodes only.
  # base64 flag tells Talos to base64-decode the config value before applying.
  # Non-cluster VMs receive an empty map.
  extra_config = contains(["controlplane", "worker"], coalesce(each.value.role, "")) ? {
    "guestinfo.talos.config"        = base64encode(local.machineconfigs[each.key])
    "guestinfo.talos.config.base64" = "true"
  } : {}

  # Block until vmtoolsd reports a guest IP (requires siderolabs/vmtoolsd-vsphere
  # in the Talos image schematic). Non-Talos VMs also benefit from this wait
  # if they run an open-vm-tools package.
  wait_for_guest_ip_timeout  = 10
  wait_for_guest_net_timeout = 10

  lifecycle {
    ignore_changes = [
      ovf_deploy,
      guest_id,
      firmware,
    ]
  }
}

# =============================================================================
# IP Derivation
# =============================================================================
#
# Prefer the vCenter-reported guest IP (via vmtoolsd) over the user-declared
# ipv4 field. The declared IP is the bootstrap fallback before vmtools starts.

locals {
  instance_ips = {
    for k, v in vsphere_virtual_machine.instances : k => (
      length([
        for ip in v.guest_ip_addresses : ip
        if !can(regex(":", ip)) && ip != "127.0.0.1"
      ]) > 0
      ? [for ip in v.guest_ip_addresses : ip if !can(regex(":", ip)) && ip != "127.0.0.1"][0]
      : local.instances_by_name[k].ipv4
    )
  }

  instance_ipv6s = {
    for k, v in vsphere_virtual_machine.instances : k => (
      try([for ip in v.guest_ip_addresses : ip if can(regex(":", ip)) && !startswith(ip, "fe80:")][0], null)
    )
  }

  instances_output = [
    for k, v in vsphere_virtual_machine.instances : {
      name     = v.name
      hostname = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = local.instance_ipv6s[k]
      status   = v.power_state
      type     = "virtual-machine"
      image    = coalesce(local.instances_by_name[k].image, "")
      role     = local.instances_by_name[k].role
    }
  ]

  controlplanes_output = [
    for k, v in vsphere_virtual_machine.instances : {
      hostname = v.name
      endpoint = local.instance_ips[k] != null ? "${local.instance_ips[k]}:50000" : null
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = local.instance_ipv6s[k]
      status   = v.power_state
      type     = "virtual-machine"
      image    = coalesce(local.instances_by_name[k].image, "")
    }
    if local.instances_by_name[k].role == "controlplane" && local.instance_ips[k] != null
  ]

  workers_output = [
    for k, v in vsphere_virtual_machine.instances : {
      hostname = v.name
      endpoint = local.instance_ips[k] != null ? "${local.instance_ips[k]}:50000" : null
      node     = local.instance_ips[k]
      name     = v.name
      ipv4     = local.instance_ips[k]
      ipv6     = local.instance_ipv6s[k]
      status   = v.power_state
      type     = "virtual-machine"
      image    = coalesce(local.instances_by_name[k].image, "")
    }
    if local.instances_by_name[k].role == "worker" && local.instance_ips[k] != null
  ]
}
