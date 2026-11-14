mock_provider "talos" {}

mock_provider "null" {
  mock_resource "null_resource" {}
}

variables {
  context_path  = "/tmp/test"
  talos_version = "1.14.5"
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
      { node = "10.0.0.20", endpoint = "10.0.0.20:50000", install_image = "factory.talos.dev/metal-installer/rpi123:v1.14.5" },
    ]
  }

  assert {
    condition     = null_resource.upgrade_controlplane["10.0.0.10"].triggers.upgrade_image == "factory.talos.dev/installer/ext123:v1.14.5"
    error_message = "A node without install_image should upgrade to the extensions installer"
  }
  assert {
    condition     = null_resource.upgrade_worker["10.0.0.20"].triggers.upgrade_image == "factory.talos.dev/metal-installer/rpi123:v1.14.5"
    error_message = "A node with install_image should upgrade to that image"
  }
}
