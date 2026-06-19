# The Hyper-V Compute module is a Terraform module for creating and managing Hyper-V
# virtual switches, image files, VHDs, and virtual machines on a Windows Hyper-V host.
# It mirrors the input/output contract of compute/incus so cluster/talos consumes either
# transparently. Provider connection details (backend, host, credentials) are read from
# HYPERV_* environment variables; no provider attributes are set here.

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
  }
}

# =============================================================================
# Network Resources
# =============================================================================

locals {
  context_effective = var.context_id != "" ? var.context_id : var.context
  network_name      = var.network_name != "" ? var.network_name : "windsor-${local.context_effective}"
}

# The hyperv_virtual_switch creates a Hyper-V virtual switch the VMs attach to.
# Supports External (bound to a host NIC, optionally NIC-teamed), Internal
# (host-VM only), Private (VM-VM only), and NAT (Internal + NetNat for
# outbound NAT and inbound port forwarding).
resource "hyperv_virtual_switch" "main" {
  count = var.create_network ? 1 : 0

  name                        = local.network_name
  switch_type                 = var.switch_type
  notes                       = var.network_description
  net_adapter_names           = var.switch_type == "External" ? var.net_adapter_names : null
  allow_management_os         = var.switch_type == "External" ? var.allow_management_os : null
  nat_name                    = var.switch_type == "NAT" ? var.nat_name : null
  nat_internal_address_prefix = var.switch_type == "NAT" ? var.nat_internal_address_prefix : null
  nat_host_address            = var.switch_type == "NAT" ? var.nat_host_address : null
}

# =============================================================================
# Port Forwards (NAT only)
# =============================================================================
#
# bench:<external_port> -> nat -> port_forward_target_ip:<internal_port>.
# Each entry creates the kernel-level NetNatStaticMapping plus an inbound
# NetFirewallRule (unless port_forward_firewall_enabled = false). port_forwards
# carries the always-on baseline composed by the platform facet (k8s/Talos
# APIs, gateway NodePorts); extra_port_forwards layers operator-supplied
# overrides (e.g. publishing :80 on the bench's LAN IP) on top.
locals {
  effective_tcp_port_forwards = merge(var.port_forwards, var.extra_port_forwards)
  effective_udp_port_forwards = merge(var.udp_port_forwards, var.extra_udp_port_forwards)
}

resource "hyperv_nat_static_mapping" "tcp" {
  for_each   = local.effective_tcp_port_forwards
  depends_on = [hyperv_virtual_switch.main]

  nat_name      = var.nat_name
  protocol      = "tcp"
  external_ip   = var.port_forward_external_ip
  external_port = tonumber(each.key)
  internal_ip   = lookup(var.port_forward_target_overrides, each.key, var.port_forward_target_ip)
  internal_port = each.value

  firewall_rule = {
    enabled = var.port_forward_firewall_enabled
    name    = "${var.port_forward_name_prefix}-tcp-${each.key}"
    profile = "Any"
  }
}

resource "hyperv_nat_static_mapping" "udp" {
  for_each   = local.effective_udp_port_forwards
  depends_on = [hyperv_virtual_switch.main]

  nat_name      = var.nat_name
  protocol      = "udp"
  external_ip   = var.port_forward_external_ip
  external_port = tonumber(each.key)
  internal_ip   = lookup(var.port_forward_target_overrides, each.key, var.port_forward_target_ip)
  internal_port = each.value

  firewall_rule = {
    enabled = var.port_forward_firewall_enabled
    name    = "${var.port_forward_name_prefix}-udp-${each.key}"
    profile = "Any"
  }
}

# =============================================================================
# Image Resources
# =============================================================================
#
# A single resource handles all three modes (url, local_path, host_path).
# Mode is implicit per the provider contract: `url` non-null = url-mode,
# `local_path` non-null = local_path-mode, both null = host_path-mode (the
# user attests the file already exists at destination_path).

resource "hyperv_image_file" "images" {
  for_each = var.images

  destination_path = each.value.destination_path
  keep_on_destroy  = each.value.keep_on_destroy
  url = each.value.url == null ? null : {
    url         = each.value.url
    checksum    = each.value.checksum
    compression = each.value.compression
  }
  local_path = each.value.local_path
}

# =============================================================================
# Instance Expansion
# =============================================================================

locals {
  expanded_instances = flatten([
    for instance in var.instances : [
      for i in range(instance.count) : {
        name                 = instance.count > 1 ? "${instance.name}-${i + 1}" : instance.name
        role                 = instance.role
        image                = instance.image
        generation           = instance.generation
        secure_boot          = instance.secure_boot
        secure_boot_template = instance.secure_boot_template
        cpu                  = instance.cpu
        memory               = instance.memory
        memory_max           = instance.memory_max
        root_disk_size       = instance.root_disk_size
        root_disk_path       = instance.root_disk_path
        ipv4 = instance.ipv4 != null && instance.count > 1 ? format("%s.%s",
          join(".", slice(split(".", split("/", instance.ipv4)[0]), 0, 3)),
          tostring(tonumber(split(".", split("/", instance.ipv4)[0])[3]) + i)
        ) : (instance.ipv4 != null ? split("/", instance.ipv4)[0] : null)
        mac_address     = instance.mac_address
        vlan_id         = instance.vlan_id
        switch_name     = instance.switch_name
        notes           = instance.notes
        desired_state   = instance.desired_state
        shutdown_mode   = instance.shutdown_mode
        dvd_iso_path    = instance.dvd_iso_path
        boot_from_dvd   = instance.boot_from_dvd
        cidata_iso_path = instance.cidata_iso_path
        index           = i
      }
    ]
  ])

  instances_by_name = { for inst in local.expanded_instances : inst.name => inst }

  default_vhd_dir = trimsuffix(var.vhd_dir, "\\")

  # Per-instance ISO path resolution. Mirrors the parent-image rule on
  # hyperv_vhd: an instance's `dvd_iso_path` may be a key into var.images
  # (use the resulting destination_path) or an absolute host path. Empty
  # string / null means no DVD attachment. We read destination_path from
  # var.images (config-known) rather than hyperv_image_file.images (which
  # errors at refresh-time when the resource isn't yet in state).
  instance_iso_paths = {
    for k, v in local.instances_by_name : k => (
      v.dvd_iso_path == null || v.dvd_iso_path == "" ? null : (
        contains(keys(var.images), v.dvd_iso_path)
        ? var.images[v.dvd_iso_path].destination_path
        : v.dvd_iso_path
      )
    )
  }

  # Second DVD slot. Same resolution rule as instance_iso_paths.
  instance_cidata_paths = {
    for k, v in local.instances_by_name : k => (
      v.cidata_iso_path == null || v.cidata_iso_path == "" ? null : (
        contains(keys(var.images), v.cidata_iso_path)
        ? var.images[v.cidata_iso_path].destination_path
        : v.cidata_iso_path
      )
    )
  }
}

# =============================================================================
# VHD Resources
# =============================================================================

# The hyperv_vhd creates the per-instance writable root disk. Differencing VHDs
# share blocks with their parent image and are the natural fit for stamping out
# many VMs from a single image_file. Falls back to a fresh dynamic VHDX when no
# parent image is bound to an instance (BYO-image path).
resource "hyperv_vhd" "instance_root" {
  for_each = local.instances_by_name

  path = each.value.root_disk_path != null ? each.value.root_disk_path : (
    "${local.default_vhd_dir}\\${each.value.name}.vhdx"
  )

  vhd_type = each.value.image != null && each.value.image != "" ? "differencing" : "dynamic"

  parent_path = each.value.image != null && each.value.image != "" ? (
    contains(keys(var.images), each.value.image)
    ? var.images[each.value.image].destination_path
    : each.value.image
  ) : null

  size_bytes = (each.value.image != null && each.value.image != "") ? null : (
    each.value.root_disk_size * 1024 * 1024 * 1024
  )

  # parent_path reads var.images.destination_path (config-known) rather than
  # hyperv_image_file.images (which errors at refresh when state is empty),
  # so the implicit dependency on the image resource is gone — restore it
  # explicitly so the parent VHDX/ISO is staged before any child VHD.
  depends_on = [hyperv_image_file.images]
}

# =============================================================================
# Compute Resources
# =============================================================================

# The hyperv_vm creates the VM with inline NIC, hard-disk, DVD, and boot_order
# blocks. Power state is driven by state.desired; Hyper-V hard-powers-off on
# destroy. The two-apply install/eject pattern (boot from ISO once, install,
# then remove the DVD on the next apply) is supported by setting
# instances[].dvd_iso_path + boot_from_dvd on apply 1, then clearing both on
# apply 2 — the provider's slot-keyed reconciliation runs Remove-VMDvdDrive
# without VM replace.
resource "hyperv_vm" "instances" {
  for_each = local.instances_by_name

  name                 = each.value.name
  generation           = each.value.generation
  secure_boot          = each.value.generation == 2 ? each.value.secure_boot : null
  secure_boot_template = each.value.generation == 2 && each.value.secure_boot ? each.value.secure_boot_template : null
  notes                = each.value.notes

  cpu = {
    count = each.value.cpu
  }

  memory = {
    startup_bytes = each.value.memory * 1024 * 1024 * 1024
    dynamic       = each.value.memory_max != null ? true : null
    min_bytes     = each.value.memory_max != null ? each.value.memory * 1024 * 1024 * 1024 : null
    max_bytes     = each.value.memory_max != null ? each.value.memory_max * 1024 * 1024 * 1024 : null
  }

  network_adapter = [
    {
      name        = "primary"
      switch_name = each.value.switch_name != null ? each.value.switch_name : local.network_name
      mac_address = each.value.mac_address
      vlan_id     = each.value.vlan_id
    },
  ]

  hard_disk_drive = [
    {
      path                = hyperv_vhd.instance_root[each.key].path
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    },
  ]

  dvd_drive = concat(
    local.instance_iso_paths[each.key] == null ? [] : [
      {
        iso_path            = local.instance_iso_paths[each.key]
        controller_number   = 0
        controller_location = 1
      },
    ],
    local.instance_cidata_paths[each.key] == null ? [] : [
      {
        iso_path            = local.instance_cidata_paths[each.key]
        controller_number   = 0
        controller_location = 2
      },
    ],
  )

  # Gen 2 only — Set-VMFirmware -BootOrder rejects gen 1 (which uses BIOS
  # category strings via Set-VMBios -StartupOrder, not currently exposed by
  # the provider). When a DVD is attached, it appears in the boot order so
  # UEFI can fall through to it on a fresh disk (Talos install-from-ISO flow);
  # boot_from_dvd controls whether DVD leads or follows the hard disk. The
  # canonical Talos workflow uses boot_from_dvd=false: UEFI tries HDD first,
  # falls through to DVD only when the disk is empty (initial install), then
  # boots from HDD on every subsequent boot once Talos is installed.
  boot_order = each.value.generation != 2 ? null : concat(
    each.value.boot_from_dvd && local.instance_iso_paths[each.key] != null ? [
      { type = "dvd_drive", controller_number = 0, controller_location = 1 },
    ] : [],
    [{ type = "hard_disk_drive", controller_number = 0, controller_location = 0 }],
    !each.value.boot_from_dvd && local.instance_iso_paths[each.key] != null ? [
      { type = "dvd_drive", controller_number = 0, controller_location = 1 },
    ] : [],
  )

  state = {
    desired       = each.value.desired_state
    shutdown_mode = each.value.shutdown_mode
  }

  # hyperv_vhd carries the implicit HDD dependency via hard_disk_drive[].path.
  # The switch and any DVD-ISO image are referenced through config-known
  # paths (not resource-instance refs), so add explicit deps to ensure they
  # exist on the host before the VM is registered.
  depends_on = [hyperv_virtual_switch.main, hyperv_image_file.images]
}
