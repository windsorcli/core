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
#     Machine secrets and per-node machineconfigs are generated inside this
#     module (not in a separate cluster-config step). This is possible because
#     guestinfo delivery happens at VM-creation time — no pre-boot ISO staging
#     required. The module sets guestinfo.talos.config at VM creation time;
#     Talos reads the GuestInfo key on the vmware platform before maintenance
#     mode and applies the config, coming up at the static IP without DHCP.
#
#   Non-cluster VMs (any other role, or no role)
#     Any image in var.images, or a blank disk when image is empty. No
#     guestinfo config is set. These VMs appear in the `instances` output but
#     not in `controlplanes` or `workers`.
#
# Dependency chain in a vSphere blueprint:
#   compute (this module) → cluster/talos (consumes controlplanes + workers +
#                           machine_secrets + client_configuration)

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
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
provider "vsphere" {}

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

# The vsphere_host data source resolves the ESXi host the provider pins OVF
# deployments to (host_system_id is mandatory for remote OVF, even with DRS).
# An empty var.host_system selects the sole host in the datacenter.
data "vsphere_host" "this" {
  name          = var.host_system != "" ? var.host_system : null
  datacenter_id = data.vsphere_datacenter.this.id
}

# =============================================================================
# Cluster Identity & Per-node Machineconfigs
# =============================================================================

locals {
  has_cluster_nodes = length([
    for k, v in local.instances_by_name : k
    if v.role == "controlplane" || v.role == "worker"
  ]) > 0

  controlplane_nodes = {
    for k, v in local.instances_by_name : k => v
    if v.role == "controlplane"
  }

  worker_nodes = {
    for k, v in local.instances_by_name : k => v
    if v.role == "worker"
  }
}

resource "talos_machine_secrets" "this" {
  count         = local.has_cluster_nodes ? 1 : 0
  talos_version = "v${var.talos_version}"
}

data "talos_machine_configuration" "controlplane" {
  for_each = local.has_cluster_nodes ? local.controlplane_nodes : {}

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this[0].machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    var.common_config_patches,
    var.controlplane_config_patches,
    lookup(var.per_node_config_patches, each.key, null),
  ])
}

data "talos_machine_configuration" "worker" {
  for_each = local.has_cluster_nodes ? local.worker_nodes : {}

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this[0].machine_secrets
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version

  config_patches = compact([
    var.common_config_patches,
    var.worker_config_patches,
    lookup(var.per_node_config_patches, each.key, null),
  ])
}

locals {
  guestinfo_configs = merge(
    { for k, v in data.talos_machine_configuration.controlplane : k => base64encode(v.machine_configuration) },
    { for k, v in data.talos_machine_configuration.worker : k => base64encode(v.machine_configuration) },
  )
}

# =============================================================================
# Instance Expansion
# =============================================================================

locals {
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
        notes = instance.notes
        index = i
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
# VM Resources
# =============================================================================
#
# ovf_deploy is a dynamic block: it fires only when the instance declares an
# image key that resolves to a URL in var.images. Non-Talos VMs with no image
# (or an image referencing a non-OVA artifact) get a blank disk instead.
#
# extra_config delivers the Talos machineconfig only when the role is
# controlplane or worker AND a config exists in local.guestinfo_configs.
# The map is generated inside this module from talos_machine_configuration
# data sources. Non-cluster VMs receive an empty extra_config map.
#
# lifecycle.ignore_changes covers ovf_deploy (initial bootstrap only), guest_id,
# and firmware — the OVA sets all three and Terraform should not fight them on
# subsequent applies.

# The vsphere_folder groups this deployment's VMs. Created only when var.folder
# is empty (the default "windsor-<context>" path); an operator-supplied folder
# is assumed to already exist and is left unmanaged.
resource "vsphere_folder" "vm" {
  count = var.folder == "" ? 1 : 0

  path          = local.vm_folder
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.this.id
}

resource "vsphere_virtual_machine" "instances" {
  for_each   = local.instances_by_name
  depends_on = [vsphere_folder.vm]

  name             = each.value.name
  resource_pool_id = local.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id
  host_system_id   = data.vsphere_host.this.id
  datacenter_id    = data.vsphere_datacenter.this.id
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
  # The base64-encoded config is generated inside this module via
  # local.guestinfo_configs. guestinfo.talos.config.base64 = "true" instructs
  # Talos to decode before applying. Non-cluster VMs receive an empty map.
  extra_config = contains(["controlplane", "worker"], each.value.role != null ? each.value.role : "") && lookup(local.guestinfo_configs, each.key, null) != null ? {
    "guestinfo.talos.config"        = local.guestinfo_configs[each.key]
    "guestinfo.talos.config.base64" = "true"
  } : {}

  # Do not block VM creation on the guest-IP waiter. With Talos'
  # vmtoolsd-guest-agent the hashicorp/vsphere waiter times out even though
  # vCenter reports a healthy guest.ipAddress + toolsOk (observed on 2.12.0);
  # node IPs are static and known from the machineconfig, so outputs derive
  # from guest_ip_addresses on refresh and the facet falls back to the declared
  # ipv4 offset in the meantime. A negative value disables each waiter.
  wait_for_guest_ip_timeout  = -1
  wait_for_guest_net_timeout = -1

  lifecycle {
    ignore_changes = [
      ovf_deploy,
      guest_id,
      firmware,
      disk,
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
      image    = local.instances_by_name[k].image != null ? local.instances_by_name[k].image : ""
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
      image    = local.instances_by_name[k].image != null ? local.instances_by_name[k].image : ""
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
      image    = local.instances_by_name[k].image != null ? local.instances_by_name[k].image : ""
    }
    if local.instances_by_name[k].role == "worker" && local.instance_ips[k] != null
  ]
}
