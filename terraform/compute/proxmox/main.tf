# The Proxmox Compute module creates Talos nocloud VMs on one or more nodes of a Proxmox VE cluster.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.116.0"
    }
  }
}

# =============================================================================
# Platform Locals
# =============================================================================

locals {
  # arm64 guests run on the virt machine with UEFI and a SCSI cloud-init drive.
  is_arm64             = var.arch == "arm64"
  machine              = local.is_arm64 ? "virt" : "q35"
  bios                 = local.is_arm64 ? "ovmf" : var.bios
  cloud_init_interface = local.is_arm64 ? "scsi1" : "ide2"
  cpu_type             = var.cpu_type != null ? var.cpu_type : (local.is_arm64 ? "host" : "x86-64-v2-AES")

  network_prefix_length = tonumber(split("/", var.network_cidr)[1])

  # Nodes that get a VM, nodes that need the images, and every other node the module reads.
  vm_nodes    = distinct([for inst in var.instances : coalesce(inst.node_name, var.node_name)])
  image_nodes = distinct([for inst in var.instances : coalesce(inst.node_name, var.node_name) if inst.image != null && inst.image != ""])
  extra_nodes = setsubtract(toset(concat(local.vm_nodes, local.image_nodes, coalesce(var.nodes, []))), toset([var.node_name]))
}

# =============================================================================
# Node and Datastore Checks
# =============================================================================

# The proxmox_virtual_environment_nodes lists the nodes of the cluster and whether each is online.
data "proxmox_virtual_environment_nodes" "cluster" {}

# The proxmox_datastores lists the datastores the caller can see on the primary node.
data "proxmox_datastores" "node" {
  node_name = var.node_name

  lifecycle {
    precondition {
      condition     = contains(data.proxmox_virtual_environment_nodes.cluster.names, var.node_name)
      error_message = "Node '${var.node_name}' is not in the Proxmox cluster, or the user lacks Sys.Audit. Set proxmox.node or proxmox.nodes to existing node names."
    }

    precondition {
      condition     = !contains(data.proxmox_virtual_environment_nodes.cluster.names, var.node_name) || try(data.proxmox_virtual_environment_nodes.cluster.online[index(data.proxmox_virtual_environment_nodes.cluster.names, var.node_name)], false)
      error_message = "Node '${var.node_name}' is offline. Start it, or set proxmox.node or proxmox.nodes to an online node."
    }

    postcondition {
      condition     = self.datastores == null || length(var.images) == 0 || contains([for d in self.datastores : d.id], var.image_datastore_id)
      error_message = "Image datastore '${var.image_datastore_id}' does not exist on node '${var.node_name}', or the user lacks Datastore.Audit on it. Create it or set proxmox.image_datastore to an existing datastore."
    }

    postcondition {
      condition = self.datastores == null || length(var.images) == 0 || !contains([for d in self.datastores : d.id], var.image_datastore_id) || anytrue([
        for d in self.datastores : contains(d.content_types, "import") if d.id == var.image_datastore_id
      ])
      error_message = "Image datastore '${var.image_datastore_id}' on node '${var.node_name}' does not allow the 'import' content type. Add 'import' to its content types."
    }

    postcondition {
      condition     = self.datastores == null || !contains(local.vm_nodes, var.node_name) || contains([for d in self.datastores : d.id], var.datastore_id)
      error_message = "VM datastore '${var.datastore_id}' does not exist on node '${var.node_name}', or the user lacks Datastore.Audit on it. Create it or set proxmox.datastore to an existing datastore."
    }
  }
}

locals {
  # The image datastore is shared storage when the primary node lists it with the shared flag.
  image_datastore_shared = try(anytrue([
    for d in data.proxmox_datastores.node.datastores : d.shared == true if d.id == var.image_datastore_id
  ]), false)
}

# The proxmox_datastores lists the datastores the caller can see on each other node.
data "proxmox_datastores" "extra" {
  for_each = local.extra_nodes

  node_name = each.key

  lifecycle {
    precondition {
      condition     = contains(data.proxmox_virtual_environment_nodes.cluster.names, each.key)
      error_message = "Node '${each.key}' is not in the Proxmox cluster, or the user lacks Sys.Audit. Set proxmox.nodes to existing node names."
    }

    precondition {
      condition     = !contains(data.proxmox_virtual_environment_nodes.cluster.names, each.key) || try(data.proxmox_virtual_environment_nodes.cluster.online[index(data.proxmox_virtual_environment_nodes.cluster.names, each.key)], false)
      error_message = "Node '${each.key}' is offline. Start it or remove it from proxmox.nodes."
    }

    postcondition {
      condition     = self.datastores == null || local.image_datastore_shared || !contains(local.image_nodes, each.key) || contains([for d in self.datastores : d.id], var.image_datastore_id)
      error_message = "Image datastore '${var.image_datastore_id}' does not exist on node '${each.key}', or the user lacks Datastore.Audit on it. Create it on every node, or mark the datastore as shared."
    }

    postcondition {
      condition = self.datastores == null || local.image_datastore_shared || !contains(local.image_nodes, each.key) || !contains([for d in self.datastores : d.id], var.image_datastore_id) || anytrue([
        for d in self.datastores : contains(d.content_types, "import") if d.id == var.image_datastore_id
      ])
      error_message = "Image datastore '${var.image_datastore_id}' on node '${each.key}' does not allow the 'import' content type. Add 'import' to its content types."
    }

    postcondition {
      condition     = self.datastores == null || !contains(local.vm_nodes, each.key) || contains([for d in self.datastores : d.id], var.datastore_id)
      error_message = "VM datastore '${var.datastore_id}' does not exist on node '${each.key}', or the user lacks Datastore.Audit on it. Create it on every node or set proxmox.datastore to an existing datastore."
    }
  }
}

# The proxmox_virtual_environment_pools lists the pools the caller can see when the module does not create the pool.
data "proxmox_virtual_environment_pools" "existing" {
  count = var.pool_id != null && !var.create_pool ? 1 : 0

  lifecycle {
    postcondition {
      condition     = contains(self.pool_ids, var.pool_id)
      error_message = "Resource pool '${var.pool_id}' does not exist, or the user lacks Pool.Audit on it. Create it with 'pveum pool add ${var.pool_id}' or set proxmox.create_pool to true."
    }
  }
}

# =============================================================================
# Pool Resources
# =============================================================================

# The proxmox_virtual_environment_pool is the resource pool the VMs join when create_pool is set.
resource "proxmox_virtual_environment_pool" "windsor" {
  count = var.pool_id != null && var.create_pool ? 1 : 0

  pool_id = var.pool_id
  comment = "Managed by Windsor (${var.context_id})"
}

locals {
  vm_pool_id = var.pool_id == null ? null : try(proxmox_virtual_environment_pool.windsor[0].pool_id, var.pool_id)
}

# =============================================================================
# Image Resources
# =============================================================================

# The proxmox_download_file pulls each image into the primary node's import storage through the PVE download-url API.
resource "proxmox_download_file" "images" {
  for_each = var.images

  node_name           = var.node_name
  datastore_id        = var.image_datastore_id
  content_type        = "import"
  url                 = each.value.url
  file_name           = each.value.file_name
  overwrite           = false
  overwrite_unmanaged = false
  upload_timeout      = each.value.upload_timeout
}

locals {
  # One download per image and node, for nodes other than node_name. A shared datastore needs none.
  extra_images = local.image_datastore_shared ? {} : {
    for pair in setproduct(keys(var.images), setintersection(local.extra_nodes, toset(local.image_nodes))) :
    "${pair[0]}/${pair[1]}" => { image = pair[0], node = pair[1] }
  }
}

# The proxmox_download_file on each other node pulls the image into that node's own import storage.
resource "proxmox_download_file" "extra_images" {
  for_each = local.extra_images

  node_name           = each.value.node
  datastore_id        = var.image_datastore_id
  content_type        = "import"
  url                 = var.images[each.value.image].url
  file_name           = var.images[each.value.image].file_name
  overwrite           = false
  overwrite_unmanaged = false
  upload_timeout      = var.images[each.value.image].upload_timeout
}

# =============================================================================
# Instance Expansion
# =============================================================================

locals {
  expanded_instances = flatten([
    for instance in var.instances : [
      for i in range(instance.count) : {
        name           = instance.count > 1 ? "${instance.name}-${i + 1}" : instance.name
        node_name      = coalesce(instance.node_name, var.node_name)
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

  # Image key to the downloaded file id on the VM's node, null for a blank or unknown key.
  instance_image_ids = {
    for k, v in local.instances_by_name : k => (
      v.image != null && v.image != "" && contains(keys(var.images), v.image)
      ? (
        v.node_name == var.node_name || local.image_datastore_shared
        ? proxmox_download_file.images[v.image].id
        : proxmox_download_file.extra_images["${v.image}/${v.node_name}"].id
      )
      : null
    )
  }
}

# =============================================================================
# Compute Resources
# =============================================================================

# The proxmox_virtual_environment_vms lists the guests the caller can see when any instance pins a vm_id.
data "proxmox_virtual_environment_vms" "existing" {
  count = anytrue([for inst in local.expanded_instances : inst.vm_id != null]) ? 1 : 0
}

locals {
  # Visible guests keyed by VM ID, used to refuse a pinned vm_id that belongs to another VM.
  existing_vms_by_id = {
    for vm in try(data.proxmox_virtual_environment_vms.existing[0].vms, []) : tostring(vm.vm_id) => vm
  }
}

# The proxmox_virtual_environment_vm boots the imported Talos disk on its node with a Proxmox cloud-init drive holding the node's network config.
resource "proxmox_virtual_environment_vm" "instances" {
  for_each = local.instances_by_name

  name        = "${each.value.name}${var.name_suffix}"
  node_name   = each.value.node_name
  vm_id       = each.value.vm_id
  pool_id     = local.vm_pool_id
  description = each.value.notes

  machine                              = local.machine
  bios                                 = local.bios
  scsi_hardware                        = "virtio-scsi-pci"
  on_boot                              = true
  started                              = true
  stop_on_destroy                      = true
  delete_unreferenced_disks_on_destroy = false

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

    precondition {
      condition = each.value.vm_id == null || (
        try(local.existing_vms_by_id[tostring(each.value.vm_id)].name, "${each.value.name}${var.name_suffix}") == "${each.value.name}${var.name_suffix}"
      )
      error_message = "vm_id ${coalesce(each.value.vm_id, 0)} belongs to an existing VM that is not ${each.value.name}${var.name_suffix}. Choose a free VM ID range."
    }
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
