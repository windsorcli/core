mock_provider "hyperv" {
  mock_data "hyperv_iso_volume" {
    defaults = {
      sha256         = "0000000000000000000000000000000000000000000000000000000000000000"
      size_bytes     = 1024
      content_base64 = ""
    }
  }
  mock_resource "hyperv_image_file" {
    defaults = {
      destination_path = "C:\\hyperv\\images\\cidata.iso"
    }
  }
}

mock_provider "talos" {
  mock_resource "talos_machine_secrets" {}
  mock_data "talos_machine_configuration" {
    defaults = {
      machine_configuration = "version: v1alpha1\nmachine:\n  type: controlplane\n  # mocked machineconfig\n"
    }
  }
}

# Minimal: 1 controlplane, 0 workers — single CIDATA ISO produced. Volume
# label is CIDATA so Talos's nocloud platform discovers it; user-data is
# the signed machineconfig from data.talos_machine_configuration; network-
# config has version: 2 at the top so cloud-init's v2 parser activates.
run "single_controlplane" {
  command = plan

  variables {
    talos_version    = "1.12.6"
    cluster_endpoint = "https://192.168.0.10:6443"
    destination_dir  = "C:/hyperv/iso"
    network = {
      cidr_block  = "192.168.0.0/22"
      gateway     = "192.168.1.0"
      nameservers = ["1.1.1.1", "8.8.8.8"]
    }
    controlplanes = [
      { hostname = "controlplane-1", node = "192.168.0.10" }
    ]
    workers = []
  }

  assert {
    condition     = length(data.hyperv_iso_volume.cidata) == 1
    error_message = "One CIDATA ISO expected for 1 controlplane + 0 workers"
  }

  assert {
    condition     = data.hyperv_iso_volume.cidata["controlplane-1"].volume_label == "CIDATA"
    error_message = "volume_label must be CIDATA"
  }

  assert {
    condition     = alltrue([for k in ["meta-data", "network-config", "user-data"] : contains(keys(data.hyperv_iso_volume.cidata["controlplane-1"].files), k)])
    error_message = "files must contain meta-data, network-config, user-data"
  }

  assert {
    condition     = startswith(data.hyperv_iso_volume.cidata["controlplane-1"].files["network-config"], "version: 2")
    error_message = "network-config must lead with 'version: 2' so cloud-init parser activates"
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 1
    error_message = "One per-node machineconfig data source expected for the single controlplane"
  }

  assert {
    condition     = length(data.talos_machine_configuration.worker) == 0
    error_message = "No worker configs expected when workers list is empty"
  }

  assert {
    condition     = hyperv_image_file.cidata["controlplane-1"].destination_path == "C:/hyperv/iso/controlplane-1-cidata.iso"
    error_message = "Empty name_suffix should leave the seed filename bare"
  }

  assert {
    condition     = hyperv_image_file.cidata["controlplane-1"].replace_while_mounted && hyperv_image_file.cidata["controlplane-1"].force_destroy
    error_message = "Seed must set replace_while_mounted and force_destroy; the VM holds it open from another state"
  }
}

# name_suffix namespaces the seed filename so two contexts sharing a host and a
# destination_dir don't write the same path.
run "name_suffix_namespaces_cidata" {
  command = plan

  variables {
    talos_version    = "1.12.6"
    cluster_endpoint = "https://192.168.0.10:6443"
    destination_dir  = "C:/hyperv/iso"
    name_suffix      = "-ctx1"
    network = {
      cidr_block  = "192.168.0.0/22"
      gateway     = "192.168.1.0"
      nameservers = ["1.1.1.1"]
    }
    controlplanes = [
      { hostname = "controlplane", node = "192.168.0.10" }
    ]
    workers = []
  }

  assert {
    condition     = hyperv_image_file.cidata["controlplane"].destination_path == "C:/hyperv/iso/controlplane-ctx1-cidata.iso"
    error_message = "Seed filename should carry name_suffix"
  }

  assert {
    condition     = data.hyperv_iso_volume.cidata["controlplane"].files["meta-data"] == yamlencode({ "instance-id" = "controlplane", "local-hostname" = "controlplane" })
    error_message = "Talos hostname must stay unsuffixed"
  }
}

# HA: 3 controlplanes + 2 workers — five CIDATA ISOs, five signed configs.
run "ha_pool" {
  command = plan

  variables {
    talos_version    = "1.12.6"
    cluster_endpoint = "https://192.168.0.10:6443"
    destination_dir  = "C:/hyperv/iso"
    network = {
      cidr_block  = "192.168.0.0/22"
      gateway     = "192.168.1.0"
      nameservers = ["1.1.1.1"]
    }
    controlplanes = [
      { hostname = "cp-1", node = "192.168.0.10" },
      { hostname = "cp-2", node = "192.168.0.11" },
      { hostname = "cp-3", node = "192.168.0.12" },
    ]
    workers = [
      { hostname = "wk-1", node = "192.168.0.20" },
      { hostname = "wk-2", node = "192.168.0.21" },
    ]
  }

  assert {
    condition     = length(data.hyperv_iso_volume.cidata) == 5
    error_message = "5 CIDATA ISOs expected (3 cp + 2 wk)"
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 3 && length(data.talos_machine_configuration.worker) == 2
    error_message = "Should produce 3 controlplane + 2 worker per-node machineconfigs"
  }
}

# Patches passthrough: common_config_patches and controlplane_config_patches
# both reach the per-node config_patches list (alongside the auto-generated
# network patch).
run "config_patches_passthrough" {
  command = plan

  variables {
    talos_version               = "1.12.6"
    cluster_endpoint            = "https://192.168.0.10:6443"
    destination_dir             = "C:/hyperv/iso"
    common_config_patches       = "cluster:\n  allowSchedulingOnControlPlanes: true\n"
    controlplane_config_patches = "machine:\n  install:\n    image: ghcr.io/test/installer:tag\n"
    network = {
      cidr_block  = "192.168.0.0/22"
      gateway     = "192.168.1.0"
      nameservers = ["1.1.1.1"]
    }
    controlplanes = [
      { hostname = "cp-1", node = "192.168.0.10" }
    ]
    workers = []
  }

  # The data source carries the patches list as input; assert the list has
  # all three entries (common + controlplane + auto-generated network).
  assert {
    condition     = length(data.talos_machine_configuration.controlplane["cp-1"].config_patches) == 3
    error_message = "config_patches list should contain common + controlplane + auto-generated network patches (3 entries)"
  }
}

# Address override: explicit address survives derivation (e.g. /24 within /22).
run "explicit_address_override" {
  command = plan

  variables {
    talos_version    = "1.12.6"
    cluster_endpoint = "https://10.0.0.10:6443"
    destination_dir  = "C:/hyperv/iso"
    network = {
      cidr_block  = "10.0.0.0/16"
      gateway     = "10.0.0.1"
      nameservers = ["1.1.1.1"]
    }
    controlplanes = [
      {
        hostname = "cp-1"
        node     = "10.0.0.10"
        address  = "10.0.0.10/24"
      }
    ]
    workers = []
  }

  assert {
    condition     = length(data.hyperv_iso_volume.cidata) == 1
    error_message = "Single CIDATA ISO expected"
  }
}

# DHCP: network-config uses dhcp4; machineconfig still bakes when cluster_endpoint is set.
run "dhcp_with_endpoint_bakes_dhcp4" {
  command = plan

  variables {
    talos_version    = "1.12.6"
    cluster_endpoint = "https://talos.plant.local:6443"
    destination_dir  = "C:/hyperv/iso"
    network = {
      dhcp        = true
      nameservers = ["1.1.1.1"]
    }
    controlplanes = [
      { hostname = "controlplane" }
    ]
    workers = []
  }

  assert {
    condition     = strcontains(data.hyperv_iso_volume.cidata["controlplane"].files["network-config"], "dhcp4: true")
    error_message = "DHCP CIDATA network-config should set dhcp4: true"
  }

  assert {
    condition     = contains(keys(data.hyperv_iso_volume.cidata["controlplane"].files), "user-data")
    error_message = "cluster_endpoint set should still bake user-data machineconfig"
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 1
    error_message = "One controlplane machineconfig expected when baking"
  }
}

# Empty cluster_endpoint skips machineconfig bake; CIDATA is network-only.
run "dhcp_without_endpoint_skips_machineconfig" {
  command = plan

  variables {
    talos_version    = "1.12.6"
    cluster_endpoint = ""
    destination_dir  = "C:/hyperv/iso"
    network = {
      dhcp = true
    }
    controlplanes = [
      { hostname = "controlplane" }
    ]
    workers = []
  }

  assert {
    condition     = talos_machine_secrets.this.talos_version == "v1.12.6"
    error_message = "Cluster identity must exist even when the machineconfig is not baked"
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 0
    error_message = "Empty cluster_endpoint should skip machineconfig data sources"
  }

  assert {
    condition     = !contains(keys(data.hyperv_iso_volume.cidata["controlplane"].files), "user-data")
    error_message = "CIDATA should omit user-data when machineconfig is not baked"
  }

  assert {
    condition     = strcontains(data.hyperv_iso_volume.cidata["controlplane"].files["network-config"], "dhcp4: true")
    error_message = "DHCP CIDATA network-config should set dhcp4: true without a bake"
  }
}
