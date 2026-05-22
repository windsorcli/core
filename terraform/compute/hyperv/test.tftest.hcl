mock_provider "hyperv" {
  mock_resource "hyperv_virtual_switch" {}
  mock_resource "hyperv_image_file" {
    defaults = {
      destination_path = "C:\\hyperv\\images\\mock.vhdx"
    }
  }
  mock_resource "hyperv_vhd" {}
  mock_resource "hyperv_vm" {}
}

# Verifies the module creates a virtual switch with the default Internal type
# and emits a windsor-{context_id} switch name when network_name is empty.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = length(hyperv_virtual_switch.main) == 1
    error_message = "Virtual switch should be created by default"
  }

  assert {
    condition     = hyperv_virtual_switch.main[0].name == "windsor-test"
    error_message = "Switch name should default to windsor-{context_id}"
  }

  assert {
    condition     = hyperv_virtual_switch.main[0].switch_type == "Internal"
    error_message = "Switch type should default to Internal"
  }

  assert {
    condition     = length(hyperv_image_file.images) == 0
    error_message = "No image_file resources expected when images map is empty"
  }

  assert {
    condition     = length(hyperv_vm.instances) == 0
    error_message = "No VMs expected when instances list is empty"
  }
}

# Tests create_network=false: no switch resource is created, but instances still
# bind their NICs to network_name as a pre-existing switch on the host.
run "external_switch_byo_network" {
  command = plan

  variables {
    context_id     = "test"
    network_name   = "lab-existing"
    create_network = false
  }

  assert {
    condition     = length(hyperv_virtual_switch.main) == 0
    error_message = "create_network=false should suppress switch creation"
  }
}

# External switch with a host NIC binding. Only valid for switch_type=External;
# net_adapter_names should be passed through.
run "external_switch" {
  command = plan

  variables {
    context_id        = "test"
    switch_type       = "External"
    net_adapter_names = ["Ethernet"]
  }

  assert {
    condition     = hyperv_virtual_switch.main[0].switch_type == "External"
    error_message = "switch_type should be External"
  }

  assert {
    condition     = length(hyperv_virtual_switch.main[0].net_adapter_names) == 1 && hyperv_virtual_switch.main[0].net_adapter_names[0] == "Ethernet"
    error_message = "net_adapter_names should bind the External switch to the named host NIC"
  }
}

# Image-file URL mode: provider downloads the VHDX and verifies SHA-256.
# Expanded instances reference the image by map key, which becomes the
# differencing-VHD parent path.
run "url_image_with_instance" {
  command = plan

  variables {
    context_id = "test"
    images = {
      talos = {
        destination_path = "C:\\hyperv\\images\\talos.vhdx"
        url              = "https://factory.talos.dev/image/test/v1.12.6/hyperv-amd64.vhdx"
        checksum         = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      }
    }
    instances = [
      {
        name           = "controlplane"
        role           = "controlplane"
        count          = 1
        image          = "talos"
        cpu            = 2
        memory         = 4
        root_disk_size = 30
        ipv4           = "10.5.0.10"
      },
    ]
  }

  assert {
    condition     = length(hyperv_image_file.images) == 1
    error_message = "Single image should produce one image_file resource"
  }

  assert {
    condition     = hyperv_image_file.images["talos"].destination_path == "C:\\hyperv\\images\\talos.vhdx"
    error_message = "image_file destination_path should match the input"
  }

  assert {
    condition     = length(hyperv_vm.instances) == 1
    error_message = "Single instance with count=1 should produce one VM"
  }

  assert {
    condition     = hyperv_vm.instances["controlplane"].name == "controlplane"
    error_message = "VM name should match instance name when count=1"
  }

  assert {
    condition     = hyperv_vm.instances["controlplane"].generation == 2
    error_message = "VM generation should default to 2"
  }

  assert {
    condition     = hyperv_vm.instances["controlplane"].cpu.count == 2
    error_message = "VM cpu.count should propagate"
  }

  assert {
    condition     = hyperv_vm.instances["controlplane"].memory.startup_bytes == 4 * 1024 * 1024 * 1024
    error_message = "VM memory.startup_bytes should be GiB-converted"
  }

  assert {
    condition     = hyperv_vhd.instance_root["controlplane"].vhd_type == "differencing"
    error_message = "Instance root VHD should be differencing when an image is bound"
  }

  assert {
    condition     = hyperv_vhd.instance_root["controlplane"].path == "C:\\hyperv\\vhds\\controlplane.vhdx"
    error_message = "Default root VHD path should be vhd_dir\\<name>.vhdx"
  }
}

# count > 1 expansion: pool stamps -1, -2 suffixes; sequential IPv4 increments.
run "instance_count_expansion" {
  command = plan

  variables {
    context_id = "test"
    instances = [
      {
        name   = "worker"
        role   = "worker"
        count  = 3
        image  = ""
        cpu    = 4
        memory = 4
        ipv4   = "10.5.0.20"
      },
    ]
  }

  assert {
    condition     = length(hyperv_vm.instances) == 3
    error_message = "count=3 should produce 3 VMs"
  }

  assert {
    condition     = contains(keys(hyperv_vm.instances), "worker-1") && contains(keys(hyperv_vm.instances), "worker-2") && contains(keys(hyperv_vm.instances), "worker-3")
    error_message = "Pool VMs should be named worker-1, worker-2, worker-3"
  }

  assert {
    condition     = hyperv_vhd.instance_root["worker-1"].vhd_type == "dynamic"
    error_message = "Empty image should produce a fresh dynamic VHDX (no parent)"
  }
}

# Dynamic memory: when memory_max is set, the module enables Hyper-V dynamic
# memory and binds startup/min/max accordingly.
run "dynamic_memory" {
  command = plan

  variables {
    context_id = "test"
    instances = [
      {
        name       = "elastic"
        count      = 1
        image      = ""
        cpu        = 2
        memory     = 4
        memory_max = 8
      },
    ]
  }

  assert {
    condition     = hyperv_vm.instances["elastic"].memory.dynamic == true
    error_message = "memory_max should opt into dynamic memory"
  }

  assert {
    condition     = hyperv_vm.instances["elastic"].memory.max_bytes == 8 * 1024 * 1024 * 1024
    error_message = "max_bytes should match memory_max in GiB"
  }
}

# url-mode image with compression: provider downloads the compressed artifact,
# verifies the SHA against the publisher's compressed-bytes checksum, then
# decompresses on the runner before streaming to the host.
run "url_image_with_compression" {
  command = plan

  variables {
    context_id = "test"
    images = {
      talos = {
        destination_path = "C:\\hyperv\\images\\talos.vhdx"
        url              = "https://factory.talos.dev/image/test/v1.12.6/hyperv-amd64.vhd.xz"
        checksum         = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        compression      = "xz"
      }
    }
  }

  assert {
    condition     = hyperv_image_file.images["talos"].url.compression == "xz"
    error_message = "url.compression should propagate to the resource"
  }

  assert {
    condition     = hyperv_image_file.images["talos"].destination_path == "C:\\hyperv\\images\\talos.vhdx"
    error_message = "destination_path should be the decompressed file's path, not the .xz path"
  }
}

# DVD attachment via images-map key: dvd_iso_path resolves through the
# images map's destination_path, mirroring the parent-image resolution rule.
# boot_from_dvd flips the gen 2 boot_order to lead with the DVD slot.
run "dvd_iso_install_flow" {
  command = plan

  variables {
    context_id = "test"
    images = {
      talos-iso = {
        destination_path = "C:/hyperv/iso/metal-amd64.iso"
        url              = "https://factory.talos.dev/image/test/v1.12.6/metal-amd64.iso"
        checksum         = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      }
    }
    instances = [
      {
        name           = "controlplane"
        role           = "controlplane"
        count          = 1
        image          = ""
        root_disk_size = 30
        dvd_iso_path   = "talos-iso"
        boot_from_dvd  = true
        generation     = 2
        secure_boot    = false
        cpu            = 2
        memory         = 4
      },
    ]
  }

  assert {
    condition     = length(hyperv_vm.instances["controlplane"].dvd_drive) == 1
    error_message = "dvd_drive should have one entry when dvd_iso_path is set"
  }

  assert {
    condition     = length(hyperv_vm.instances["controlplane"].boot_order) == 2
    error_message = "boot_order should list both DVD and HDD when boot_from_dvd is true"
  }

  assert {
    condition     = hyperv_vm.instances["controlplane"].boot_order[0].type == "dvd_drive"
    error_message = "boot_from_dvd=true should put dvd_drive first in boot_order"
  }
}

# DVD attached with boot_from_dvd=false: HDD leads, DVD trails. This is the
# canonical Talos install-from-ISO flow — UEFI tries HDD first (boots Talos
# once installed), falls through to DVD on a fresh disk for the initial install.
run "dvd_attached_hdd_first_uefi_fallthrough" {
  command = plan

  variables {
    context_id = "test"
    images = {
      talos-iso = {
        destination_path = "C:/hyperv/iso/metal-amd64.iso"
      }
    }
    instances = [
      {
        name          = "node"
        count         = 1
        image         = ""
        generation    = 2
        secure_boot   = false
        cpu           = 2
        memory        = 4
        dvd_iso_path  = "talos-iso"
        boot_from_dvd = false
      },
    ]
  }

  assert {
    condition     = length(hyperv_vm.instances["node"].boot_order) == 2
    error_message = "boot_order should list both HDD and DVD when DVD is attached"
  }

  assert {
    condition     = hyperv_vm.instances["node"].boot_order[0].type == "hard_disk_drive"
    error_message = "boot_from_dvd=false should put HDD first so UEFI tries the disk before falling through to DVD"
  }

  assert {
    condition     = hyperv_vm.instances["node"].boot_order[1].type == "dvd_drive"
    error_message = "DVD should still appear in boot_order as a fallback for fresh disks"
  }
}

# Without dvd_iso_path: dvd_drive list is empty and boot_order leads with HDD.
run "no_dvd_boots_from_disk" {
  command = plan

  variables {
    context_id = "test"
    instances = [
      {
        name        = "node"
        count       = 1
        image       = ""
        generation  = 2
        secure_boot = false
        cpu         = 1
        memory      = 2
      },
    ]
  }

  assert {
    condition     = length(hyperv_vm.instances["node"].dvd_drive) == 0
    error_message = "dvd_drive should be empty when dvd_iso_path is unset"
  }

  assert {
    condition     = length(hyperv_vm.instances["node"].boot_order) == 1 && hyperv_vm.instances["node"].boot_order[0].type == "hard_disk_drive"
    error_message = "Without DVD, boot_order should contain only the hard_disk_drive entry"
  }
}

# secure_boot_template propagates only when secure_boot is true on a gen 2 VM
# (Hyper-V rejects the template on gen 1 and ignores it when secure_boot=false).
run "secure_boot_template_for_windows" {
  command = plan

  variables {
    context_id = "test"
    instances = [
      {
        name                 = "win-app"
        count                = 1
        image                = ""
        generation           = 2
        secure_boot          = true
        secure_boot_template = "MicrosoftWindows"
        cpu                  = 2
        memory               = 4
      },
    ]
  }

  assert {
    condition     = hyperv_vm.instances["win-app"].secure_boot_template == "MicrosoftWindows"
    error_message = "secure_boot_template should propagate when secure_boot is true on gen 2"
  }
}

# CIDATA ISO attached as a second DVD alongside the OS ISO. Verifies that
# both entries land with the expected slot identifiers (1 = OS, 2 = CIDATA)
# and that the CIDATA path is NOT in boot_order (it's data, not bootable).
run "cidata_iso_attached_as_second_dvd" {
  command = plan

  variables {
    context_id = "test"
    images = {
      talos-iso = {
        destination_path = "C:/hyperv/iso/metal-amd64.iso"
      }
      cp-cidata = {
        destination_path = "C:/hyperv/iso/cp-cidata.iso"
      }
    }
    instances = [
      {
        name            = "controlplane"
        role            = "controlplane"
        count           = 1
        image           = ""
        dvd_iso_path    = "talos-iso"
        cidata_iso_path = "cp-cidata"
        boot_from_dvd   = false
        generation      = 2
        secure_boot     = false
        cpu             = 2
        memory          = 4
      },
    ]
  }

  assert {
    condition     = length(hyperv_vm.instances["controlplane"].dvd_drive) == 2
    error_message = "Two DVDs expected when both dvd_iso_path and cidata_iso_path are set"
  }

  assert {
    condition     = hyperv_vm.instances["controlplane"].dvd_drive[0].controller_location == 1
    error_message = "OS ISO should land at controller_location 1"
  }

  assert {
    condition     = hyperv_vm.instances["controlplane"].dvd_drive[1].controller_location == 2
    error_message = "CIDATA ISO should land at controller_location 2"
  }

  assert {
    condition     = length([for entry in hyperv_vm.instances["controlplane"].boot_order : entry if entry.controller_location == 2]) == 0
    error_message = "CIDATA slot must not appear in boot_order — it's runtime-discovered data, not a boot source"
  }
}

# CIDATA ISO without an OS ISO: the cidata_iso_path entry survives but takes
# slot 2 (not slot 1) — slot mapping is positional intent, not packed indexing.
run "cidata_iso_without_os_iso" {
  command = plan

  variables {
    context_id = "test"
    images = {
      seed = {
        destination_path = "C:/hyperv/iso/seed.iso"
      }
    }
    instances = [
      {
        name            = "preprovisioned"
        count           = 1
        image           = "" # bring-your-own VHDX would normally have a parent here; testing the orthogonal CIDATA path
        cidata_iso_path = "seed"
        generation      = 2
        secure_boot     = false
        cpu             = 2
        memory          = 2
      },
    ]
  }

  assert {
    condition     = length(hyperv_vm.instances["preprovisioned"].dvd_drive) == 1
    error_message = "Single DVD expected when only cidata_iso_path is set"
  }

  assert {
    condition     = hyperv_vm.instances["preprovisioned"].dvd_drive[0].controller_location == 2
    error_message = "CIDATA-only configuration still pins the CIDATA at slot 2; slot 1 stays empty rather than packing"
  }
}

# Overlap validation: extra_port_forwards must not reuse an external port
# already in port_forwards. The platform-hyperv facet builds port_forwards
# (k8s/Talos APIs, gateway NodePorts) and layers operator-supplied
# extra_port_forwards (gateway.publish_ports) on top; without this gate, an
# operator picking an in-use bench port would silently override the baseline
# (e.g. clobber the worker-1 Talos API forward).
run "extra_port_forwards_collision_rejected" {
  command = plan

  variables {
    context_id = "test"
    port_forwards = {
      "50000" = 50000
      "50001" = 50000
    }
    extra_port_forwards = {
      "50000" = 30080
    }
  }

  expect_failures = [
    var.extra_port_forwards,
  ]
}

# Generation 1 VM: gen 1 selects the BIOS boot path. secure_boot is forced null
# in main.tf (validator rejects it on gen 1), but the mock provider doesn't
# expose computed config-on-write back during plan, so we only check generation.
run "generation_one" {
  command = plan

  variables {
    context_id = "test"
    instances = [
      {
        name       = "legacy"
        count      = 1
        image      = ""
        generation = 1
        cpu        = 1
        memory     = 2
      },
    ]
  }

  assert {
    condition     = hyperv_vm.instances["legacy"].generation == 1
    error_message = "Gen 1 VM should report generation=1"
  }
}
