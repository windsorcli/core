mock_provider "proxmox" {
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:import/talos.qcow2"
    }
  }
  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      vm_id                   = 100
      started                 = true
      network_interface_names = ["lo", "ens18"]
      ipv4_addresses          = [["127.0.0.1"], ["10.5.0.50"]]
    }
  }
}

# Top-level variables shared across all runs.
variables {
  context_id      = "test"
  node_name       = "pve"
  network_cidr    = "10.5.0.0/24"
  network_gateway = "10.5.0.1"
  images = {
    talos = {
      url       = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.14.2/nocloud-amd64.qcow2"
      file_name = "talos-v1.14.2-ce4c9805-amd64-test.qcow2"
    }
  }
}

# No instances: the module creates no VMs.
run "empty_module" {
  command = plan

  variables {
    images = {}
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.instances) == 0
    error_message = "No VMs expected when instances list is empty"
  }

  assert {
    condition     = length(proxmox_download_file.images) == 0
    error_message = "No downloads expected when images is empty"
  }
}

# Image download: import content type into the image datastore on the target node.
run "image_download" {
  command = plan

  assert {
    condition     = proxmox_download_file.images["talos"].content_type == "import"
    error_message = "images must download as the import content type"
  }

  assert {
    condition     = proxmox_download_file.images["talos"].datastore_id == "local"
    error_message = "images must land in image_datastore_id"
  }

  assert {
    condition     = proxmox_download_file.images["talos"].node_name == "pve"
    error_message = "images must download on node_name"
  }

  assert {
    condition     = proxmox_download_file.images["talos"].upload_timeout == 1800
    error_message = "upload_timeout must default to 1800 seconds"
  }

  assert {
    condition     = proxmox_download_file.images["talos"].overwrite_unmanaged == false
    error_message = "images must fail rather than replace a same-named file Terraform does not manage"
  }
}

# Shared-host guards: no pool by default, and destroy removes only disks the VM references.
run "shared_host_defaults" {
  command = plan

  variables {
    instances = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].pool_id == null
    error_message = "pool_id must default to null"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].delete_unreferenced_disks_on_destroy == false
    error_message = "destroy must not delete unreferenced disks that share the VM's ID"
  }

  assert {
    condition     = local.instances_by_name["controlplane"].vm_id == null
    error_message = "vm_id must be left to Proxmox when unset"
  }
}

# Pool: every VM joins pool_id.
run "pool_membership" {
  command = plan

  variables {
    pool_id = "windsor"
    instances = [
      { name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10" },
      { name = "worker", role = "worker", image = "talos", ipv4 = "10.5.0.20" },
    ]
  }

  assert {
    condition     = alltrue([for vm in proxmox_virtual_environment_vm.instances : vm.pool_id == "windsor"])
    error_message = "every VM must join pool_id"
  }
}

# Static controlplane: sizing, platform defaults, cloud-init network, and disk import.
run "static_controlplane" {
  command = plan

  variables {
    network_nameservers = ["1.1.1.1"]
    instances = [{
      name           = "controlplane"
      role           = "controlplane"
      image          = "talos"
      ipv4           = "10.5.0.10"
      cpu            = 2
      memory         = 4
      root_disk_size = 40
      notes          = "Talos control plane node"
    }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].name == "controlplane"
    error_message = "VM name must match the instance name when count is 1"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].cpu[0].cores == 2
    error_message = "cpu cores must come from instance.cpu"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].cpu[0].type == "x86-64-v2-AES"
    error_message = "amd64 cpu type must default to x86-64-v2-AES"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].memory[0].dedicated == 4096
    error_message = "memory must convert GiB to MiB"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].memory[0].floating == 0
    error_message = "memory ballooning must be off"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].machine == "q35"
    error_message = "amd64 guests must use the q35 machine"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].bios == "seabios"
    error_message = "amd64 bios must default to seabios"
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.instances["controlplane"].efi_disk) == 0
    error_message = "seabios guests must not get an EFI disk"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].scsi_hardware == "virtio-scsi-pci"
    error_message = "the SCSI controller must be virtio-scsi-pci"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].disk[0].size == 40
    error_message = "root disk size must come from instance.root_disk_size"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].initialization[0].type == "nocloud"
    error_message = "cloud-init must use the nocloud format"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].initialization[0].interface == "ide2"
    error_message = "amd64 cloud-init drive must sit on ide2"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].initialization[0].ip_config[0].ipv4[0].address == "10.5.0.10/24"
    error_message = "static ipv4 must be written to cloud-init with the network prefix"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].initialization[0].ip_config[0].ipv4[0].gateway == "10.5.0.1"
    error_message = "gateway must be written to cloud-init for static guests"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].initialization[0].dns[0].servers == tolist(["1.1.1.1"])
    error_message = "nameservers must be written to cloud-init"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].agent[0].wait_for_ip[0].disabled == true
    error_message = "static guests must not wait on the agent for an IP"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].stop_on_destroy == true
    error_message = "VMs must stop rather than shut down on destroy"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].description == "Talos control plane node"
    error_message = "description must carry the instance notes"
  }

  assert {
    condition     = tolist(proxmox_virtual_environment_vm.instances["controlplane"].tags) == tolist(["windsor", "test", "controlplane"])
    error_message = "tags must carry windsor, the context id, and the role"
  }
}

# Static controlplane outputs: Talos API endpoint and the static network patch for cluster/talos.
run "static_controlplane_outputs" {
  command = apply

  variables {
    network_nameservers = ["1.1.1.1"]
    instances           = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].disk[0].import_from == "local:import/talos.qcow2"
    error_message = "the root disk must import the downloaded image"
  }

  assert {
    condition     = output.controlplanes[0].endpoint == "10.5.0.10:50000"
    error_message = "controlplane endpoint must be the static IP on the Talos API port"
  }

  assert {
    condition     = output.controlplanes[0].node == "10.5.0.10"
    error_message = "controlplane node must be the declared static IP, not the agent report"
  }

  assert {
    condition     = yamldecode(output.controlplanes[0].config_patches).machine.network.interfaces[0].addresses[0] == "10.5.0.10/24"
    error_message = "controlplane output must carry the static address patch"
  }

  assert {
    condition     = yamldecode(output.controlplanes[0].config_patches).machine.network.interfaces[0].routes[0].gateway == "10.5.0.1"
    error_message = "controlplane output must carry the default route patch"
  }

  assert {
    condition     = output.controlplanes[0].instance_id == "100"
    error_message = "instance_id must surface the Proxmox vm_id"
  }

  assert {
    condition     = length(output.workers) == 0
    error_message = "no workers expected"
  }

  assert {
    condition     = output.instances[0].role == "controlplane" && output.instances[0].status == "running"
    error_message = "instances output must carry role and status"
  }
}

# Pool expansion: count > 1 names nodes -N, increments the host octet, and offsets vm_id.
run "worker_pool" {
  command = plan

  variables {
    instances = [{ name = "worker", role = "worker", image = "talos", ipv4 = "10.5.0.20", count = 3, vm_id = 200 }]
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.instances) == 3
    error_message = "count = 3 must create three VMs"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["worker-3"].initialization[0].ip_config[0].ipv4[0].address == "10.5.0.22/24"
    error_message = "third worker must get the starting address plus two"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["worker-2"].vm_id == 201
    error_message = "vm_id must increment across the pool"
  }
}

# Name suffix keeps several contexts apart on one node.
run "name_suffix" {
  command = plan

  variables {
    name_suffix = "-prod"
    instances   = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].name == "controlplane-prod"
    error_message = "VM name must carry name_suffix"
  }
}

# DHCP guest: cloud-init requests dhcp and the IP comes from the agent report on the ethernet NIC.
run "dhcp_worker_uses_agent_ip" {
  command = apply

  variables {
    instances = [{ name = "worker", role = "worker", image = "talos" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["worker"].initialization[0].ip_config[0].ipv4[0].address == "dhcp"
    error_message = "DHCP guests must request dhcp from cloud-init"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["worker"].agent[0].wait_for_ip[0].ipv4 == true
    error_message = "DHCP guests must wait on the agent for an IPv4 address"
  }

  assert {
    condition     = output.workers[0].node == "10.5.0.50"
    error_message = "DHCP worker node must be the agent IPv4 on the ethernet NIC, not loopback"
  }

  assert {
    condition     = output.workers[0].config_patches == ""
    error_message = "DHCP workers carry no static network patch"
  }
}

# DHCP guest with no agent report yet: the node is left out of the cluster outputs.
run "dhcp_without_agent_ip_is_omitted" {
  command = apply

  override_resource {
    target = proxmox_virtual_environment_vm.instances
    values = {
      vm_id                   = 100
      started                 = true
      network_interface_names = []
      ipv4_addresses          = []
    }
  }

  variables {
    instances = [{ name = "controlplane", role = "controlplane", image = "talos" }]
  }

  assert {
    condition     = length(output.controlplanes) == 0
    error_message = "a DHCP node without an agent IP must not appear in controlplanes"
  }

  assert {
    condition     = output.instances[0].ipv4 == null
    error_message = "instances must report a null ipv4 until the agent reports one"
  }
}

# Blank disk: an instance with no image key does not import a disk.
run "blank_disk_without_image" {
  command = plan

  variables {
    instances = [{ name = "utility", ipv4 = "10.5.0.30" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["utility"].disk[0].import_from == null
    error_message = "an instance without an image must not import a disk"
  }
}

# Network attachment: bridge and VLAN tag flow to the NIC.
run "network_device" {
  command = plan

  variables {
    network_bridge = "vmbr1"
    vlan_id        = 30
    instances      = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10", mac_address = "BC:24:11:00:00:10" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].network_device[0].bridge == "vmbr1"
    error_message = "NIC must attach to network_bridge"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].network_device[0].vlan_id == 30
    error_message = "NIC must carry vlan_id"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].network_device[0].mac_address == "BC:24:11:00:00:10"
    error_message = "NIC must carry the instance mac_address"
  }
}

# ovmf firmware on amd64 adds a 4m EFI disk without pre-enrolled keys.
run "ovmf_adds_efi_disk" {
  command = plan

  variables {
    bios      = "ovmf"
    instances = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].efi_disk[0].type == "4m"
    error_message = "ovmf must add a 4m EFI disk"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].efi_disk[0].pre_enrolled_keys == false
    error_message = "EFI disk must not pre-enroll Secure Boot keys"
  }
}

# arm64 selects the virt machine, OVMF, the host CPU, and a SCSI cloud-init drive.
run "arm64_defaults" {
  command = plan

  variables {
    arch      = "arm64"
    instances = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].machine == "virt"
    error_message = "arm64 guests must use the virt machine"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].bios == "ovmf"
    error_message = "arm64 guests must use ovmf"
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.instances["controlplane"].efi_disk) == 1
    error_message = "arm64 guests must get an EFI disk"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].cpu[0].type == "host"
    error_message = "arm64 cpu type must default to host"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].initialization[0].interface == "scsi1"
    error_message = "arm64 cloud-init drive must sit on scsi1"
  }
}

# Explicit cpu_type wins over the architecture default.
run "cpu_type_override" {
  command = plan

  variables {
    cpu_type  = "host"
    instances = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10" }]
  }

  assert {
    condition     = proxmox_virtual_environment_vm.instances["controlplane"].cpu[0].type == "host"
    error_message = "cpu_type must override the default"
  }
}

# A compressed image file name is rejected.
run "rejects_compressed_image" {
  command = plan

  variables {
    images = {
      talos = {
        url       = "https://factory.talos.dev/image/x/v1.14.2/nocloud-amd64.raw.xz"
        file_name = "talos.raw.xz"
      }
    }
  }

  expect_failures = [var.images]
}

# An unknown architecture is rejected.
run "rejects_unknown_arch" {
  command = plan

  variables {
    arch = "riscv64"
  }

  expect_failures = [var.arch]
}

# An out-of-range VLAN tag is rejected.
run "rejects_invalid_vlan" {
  command = plan

  variables {
    vlan_id = 4095
  }

  expect_failures = [var.vlan_id]
}

# A root disk below the Talos minimum is rejected.
run "rejects_small_root_disk" {
  command = plan

  variables {
    instances = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10", root_disk_size = 8 }]
  }

  expect_failures = [var.instances]
}

# A vm_id below the Proxmox minimum is rejected.
run "rejects_low_vm_id" {
  command = plan

  variables {
    instances = [{ name = "controlplane", role = "controlplane", image = "talos", ipv4 = "10.5.0.10", vm_id = 99 }]
  }

  expect_failures = [var.instances]
}
