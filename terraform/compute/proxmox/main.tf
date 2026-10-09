# The Proxmox Compute module creates Talos nocloud VMs on a single Proxmox VE node.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116"
    }
  }
}

# =============================================================================
# Platform Locals
# =============================================================================

locals {
  context_effective = var.context_id != "" ? var.context_id : var.context

  # arm64 guests run on the virt machine with UEFI and a SCSI cloud-init drive.
  is_arm64             = var.arch == "arm64"
  machine              = local.is_arm64 ? "virt" : "q35"
  bios                 = local.is_arm64 ? "ovmf" : var.bios
  cloud_init_interface = local.is_arm64 ? "scsi1" : "ide2"
  cpu_type             = var.cpu_type != null ? var.cpu_type : (local.is_arm64 ? "host" : "x86-64-v2-AES")

  network_prefix_length = tonumber(split("/", var.network_cidr)[1])
}

# =============================================================================
# Image Resources
# =============================================================================

# The proxmox_download_file pulls each image into the node's import storage through the PVE download-url API.
resource "proxmox_download_file" "images" {
  for_each = var.images

  node_name      = var.node_name
  datastore_id   = var.image_datastore_id
  content_type   = "import"
  url            = each.value.url
  file_name      = each.value.file_name
  overwrite      = false
  upload_timeout = each.value.upload_timeout
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
        vm_id          = instance.vm_id != null ? instance.vm_id + i : null
        mac_address    = instance.mac_address
        ipv4 = instance.ipv4 != null && instance.count > 1 ? format("%s.%s",
          join(".", slice(split(".", split("/", instance.ipv4)[0]), 0, 3)),
          tostring(tonumber(split(".", split("/", instance.ipv4)[0])[3]) + i)
        ) : (instance.ipv4 != null ? split("/", instance.ipv4)[0] : null)
        notes = instance.notes
      }
    ]
  ])

  instances_by_name = { for inst in local.expanded_instances : inst.name => inst }

  # Image key to downloaded file id, null for a blank or unknown key.
  instance_image_ids = {
    for k, v in local.instances_by_name : k => (
      v.image != null && v.image != "" && contains(keys(var.images), v.image)
      ? proxmox_download_file.images[v.image].id
      : null
    )
  }
}

# =============================================================================
# Compute Resources
# =============================================================================

# The proxmox_virtual_environment_vm boots the imported Talos disk with a Proxmox cloud-init drive holding the node's network config.
resource "proxmox_virtual_environment_vm" "instances" {
  for_each = local.instances_by_name

  name        = "${each.value.name}${var.name_suffix}"
  node_name   = var.node_name
  vm_id       = each.value.vm_id
  description = each.value.notes
  tags        = compact(["windsor", local.context_effective, each.value.role])

  machine         = local.machine
  bios            = local.bios
  scsi_hardware   = "virtio-scsi-pci"
  on_boot         = true
  started         = true
  stop_on_destroy = true

  cpu {
    cores = each.value.cpu
    type  = local.cpu_type
  }

  memory {
    dedicated = each.value.memory * 1024
    floating  = 0
  }

  agent {
    enabled = true
    timeout = var.agent_timeout
    wait_for_ip {
      ipv4     = each.value.ipv4 == null
      disabled = each.value.ipv4 != null
    }
  }

  network_device {
    bridge      = var.network_bridge
    vlan_id     = var.vlan_id
    mac_address = each.value.mac_address
    model       = "virtio"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    import_from  = local.instance_image_ids[each.key]
    file_format  = "raw"
    size         = each.value.root_disk_size
    discard      = "on"
    ssd          = true
  }

  dynamic "efi_disk" {
    for_each = local.bios == "ovmf" ? [1] : []
    content {
      datastore_id      = var.datastore_id
      type              = "4m"
      pre_enrolled_keys = false
    }
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = local.cloud_init_interface
    type         = "nocloud"

    ip_config {
      ipv4 {
        address = each.value.ipv4 != null ? "${each.value.ipv4}/${local.network_prefix_length}" : "dhcp"
        gateway = each.value.ipv4 != null ? var.network_gateway : null
      }
    }

    dns {
      servers = length(var.network_nameservers) > 0 ? var.network_nameservers : null
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [disk[0].import_from]
  }
}

# =============================================================================
# IP Derivation
# =============================================================================

locals {
  # Agent-reported IPv4 on the guest's ethernet NICs, skipping link-local addresses.
  guest_ipv4s = {
    for k, v in proxmox_virtual_environment_vm.instances : k => try(flatten([
      for i, name in v.network_interface_names : [
        for ip in v.ipv4_addresses[i] : ip if !startswith(ip, "169.254.")
      ] if can(regex("^(eth|en)", name))
    ]), [])
  }

  instance_ips = {
    for k, v in proxmox_virtual_environment_vm.instances : k => (
      local.instances_by_name[k].ipv4 != null
      ? local.instances_by_name[k].ipv4
      : try(local.guest_ipv4s[k][0], null)
    )
  }

  # Per-node static address patch for cluster/talos to apply.
  node_network_patches = {
    for k, v in local.instances_by_name : k => (
      v.ipv4 == null ? "" : yamlencode({
        machine = {
          network = {
            interfaces = [{
              deviceSelector = { physical = true }
              dhcp           = false
              addresses      = ["${v.ipv4}/${local.network_prefix_length}"]
              routes         = [{ network = "0.0.0.0/0", gateway = var.network_gateway }]
            }]
            nameservers = var.network_nameservers
          }
        }
      })
    )
  }

  instances_output = [
    for k, v in proxmox_virtual_environment_vm.instances : {
      name        = v.name
      hostname    = k
      ipv4        = local.instance_ips[k]
      ipv6        = null
      status      = v.started ? "running" : "stopped"
      type        = "virtual-machine"
      image       = local.instances_by_name[k].image != null ? local.instances_by_name[k].image : ""
      role        = local.instances_by_name[k].role
      instance_id = tostring(v.vm_id)
    }
  ]

  controlplanes_output = [
    for k, v in proxmox_virtual_environment_vm.instances : {
      hostname       = k
      endpoint       = "${local.instance_ips[k]}:50000"
      node           = local.instance_ips[k]
      name           = v.name
      ipv4           = local.instance_ips[k]
      status         = v.started ? "running" : "stopped"
      type           = "virtual-machine"
      image          = local.instances_by_name[k].image != null ? local.instances_by_name[k].image : ""
      instance_id    = tostring(v.vm_id)
      config_patches = local.node_network_patches[k]
    }
    if local.instances_by_name[k].role == "controlplane" && local.instance_ips[k] != null
  ]

  workers_output = [
    for k, v in proxmox_virtual_environment_vm.instances : {
      hostname       = k
      endpoint       = "${local.instance_ips[k]}:50000"
      node           = local.instance_ips[k]
      name           = v.name
      ipv4           = local.instance_ips[k]
      status         = v.started ? "running" : "stopped"
      type           = "virtual-machine"
      image          = local.instances_by_name[k].image != null ? local.instances_by_name[k].image : ""
      instance_id    = tostring(v.vm_id)
      config_patches = local.node_network_patches[k]
    }
    if local.instances_by_name[k].role == "worker" && local.instance_ips[k] != null
  ]
}
