mock_provider "talos" {}

mock_provider "null" {
  mock_resource "null_resource" {}
}

variables {
  context_path  = "/tmp/test"
  talos_version = "1.14.6"
}

# Verifies that no upgrade runs without extensions
run "no_extensions_skips_upgrade" {
  command = plan

  variables {
    controlplanes = [{ node = "10.0.0.10", endpoint = "10.0.0.10:50000" }]
  }

  assert {
    condition     = length(null_resource.upgrade_controlplane) == 0
    error_message = "Should not upgrade nodes when no extensions are requested"
  }
}

# Verifies that nodes upgrade to the extensions installer unless they set install_image
run "install_image_replaces_extensions_installer" {
  command = plan

  override_resource {
    target          = talos_image_factory_schematic.this[0]
    override_during = plan
    values = {
      id = "ext123"
    }
  }

  variables {
    extensions = ["siderolabs/iscsi-tools"]
    controlplanes = [
      { node = "10.0.0.10", endpoint = "10.0.0.10:50000" },
    ]
    workers = [
      { node = "10.0.0.20", endpoint = "10.0.0.20:50000", install_image = "factory.talos.dev/metal-installer/rpi123:v${var.talos_version}" },
    ]
  }

  assert {
    condition     = null_resource.upgrade_controlplane["10.0.0.10"].triggers.upgrade_image == "factory.talos.dev/installer/ext123:v${var.talos_version}"
    error_message = "A node without install_image should upgrade to the extensions installer"
  }
  assert {
    condition     = null_resource.upgrade_worker["10.0.0.20"].triggers.upgrade_image == "factory.talos.dev/metal-installer/rpi123:v${var.talos_version}"
    error_message = "A node with install_image should upgrade to that image"
  }
}

# Verifies that a node's overlay joins the extensions in one schematic on the metal installer
run "overlay_joins_extensions_schematic" {
  command = plan

  override_resource {
    target          = talos_image_factory_schematic.this[0]
    override_during = plan
    values = {
      id = "ext123"
    }
  }

  override_resource {
    target          = talos_image_factory_schematic.overlay["rpi_5"]
    override_during = plan
    values = {
      id = "rpi5ext"
    }
  }

  variables {
    extensions = ["siderolabs/iscsi-tools"]
    controlplanes = [
      { node = "10.0.0.10", endpoint = "10.0.0.10:50000", overlay = { name = "rpi_5", image = "siderolabs/sbc-raspberrypi" } },
    ]
    workers = [
      { node = "10.0.0.20", endpoint = "10.0.0.20:50000" },
    ]
  }

  assert {
    condition     = yamldecode(talos_image_factory_schematic.overlay["rpi_5"].schematic).overlay == { name = "rpi_5", image = "siderolabs/sbc-raspberrypi" }
    error_message = "The overlay schematic should hold the node's overlay"
  }
  assert {
    condition     = yamldecode(talos_image_factory_schematic.overlay["rpi_5"].schematic).customization.systemExtensions.officialExtensions == ["siderolabs/iscsi-tools"]
    error_message = "The overlay schematic should hold the extensions"
  }
  assert {
    condition     = null_resource.upgrade_controlplane["10.0.0.10"].triggers.upgrade_image == "factory.talos.dev/metal-installer/rpi5ext:v${var.talos_version}"
    error_message = "A node with an overlay should upgrade to the metal installer of the overlay schematic"
  }
  assert {
    condition     = null_resource.upgrade_worker["10.0.0.20"].triggers.upgrade_image == "factory.talos.dev/installer/ext123:v${var.talos_version}"
    error_message = "A node without an overlay should upgrade to the extensions installer"
  }
}

# Verifies that base extensions join the schematic ahead of the requested extensions on the chosen installer
run "base_extensions_and_installer" {
  command = plan

  override_resource {
    target          = talos_image_factory_schematic.this[0]
    override_during = plan
    values = {
      id = "qga123"
    }
  }

  variables {
    base_extensions = ["siderolabs/qemu-guest-agent"]
    extensions      = ["siderolabs/iscsi-tools", "siderolabs/qemu-guest-agent"]
    installer       = "nocloud-installer"
    controlplanes   = [{ node = "10.0.0.10", endpoint = "10.0.0.10:50000" }]
  }

  assert {
    condition     = yamldecode(talos_image_factory_schematic.this[0].schematic).customization.systemExtensions.officialExtensions == ["siderolabs/qemu-guest-agent", "siderolabs/iscsi-tools"]
    error_message = "The schematic should hold the base extensions, then the requested extensions, without duplicates"
  }
  assert {
    condition     = null_resource.upgrade_controlplane["10.0.0.10"].triggers.upgrade_image == "factory.talos.dev/nocloud-installer/qga123:v${var.talos_version}"
    error_message = "A node should upgrade to the chosen installer"
  }
}

# Verifies that base extensions alone do not upgrade nodes
run "base_extensions_alone_skip_upgrade" {
  command = plan

  variables {
    base_extensions = ["siderolabs/qemu-guest-agent"]
    controlplanes   = [{ node = "10.0.0.10", endpoint = "10.0.0.10:50000" }]
  }

  assert {
    condition     = length(null_resource.upgrade_controlplane) == 0
    error_message = "Should not upgrade nodes when only base extensions are set"
  }
}

# Verifies that the installer rejects names outside the supported set
run "installer_rejects_unknown_name" {
  command = plan

  variables {
    installer = "metal-installer"
  }

  expect_failures = [var.installer]
}
