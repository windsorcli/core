mock_provider "hcloud" {}
mock_provider "imager" {}

variables {
  context_id   = "test123"
  context_path = ""
  location     = "fsn1"
  network_zone = "eu-central"
  network_cidr = "10.5.0.0/16"
}

run "minimal_single_controlplane" {
  command = plan

  variables {
    instances = [
      { name = "controlplane", role = "controlplane", count = 1, server_type = "cx22" },
    ]
  }

  assert {
    condition     = hcloud_network.this.ip_range == "10.5.0.0/16"
    error_message = "Private network should use the provided CIDR."
  }

  assert {
    condition     = hcloud_network_subnet.this.ip_range == "10.5.0.0/24"
    error_message = "A /24 node subnet should be carved from a /16 network at the base."
  }

  assert {
    condition     = length(hcloud_server.this) == 1
    error_message = "Exactly one server should be planned for a single control plane."
  }

  assert {
    condition     = hcloud_server.this["controlplane-1"].server_type == "cx22"
    error_message = "Server type should match the group's server_type."
  }

  assert {
    condition     = length(imager_image.this) == 1 && contains(keys(imager_image.this), "x86")
    error_message = "An x86 snapshot should be built for a cx22 control plane."
  }

  assert {
    condition     = hcloud_server_network.this["controlplane-1"].ip == "10.5.0.10"
    error_message = "First control plane should get private IP .10."
  }
}

run "ha_mixed_architecture" {
  command = plan

  variables {
    instances = [
      { name = "controlplane", role = "controlplane", count = 3, server_type = "cx22" },
      { name = "worker", role = "worker", count = 2, server_type = "cax21" },
    ]
  }

  assert {
    condition     = length(hcloud_server.this) == 5
    error_message = "Three control planes plus two workers should be five servers."
  }

  assert {
    condition     = length(imager_image.this) == 2
    error_message = "Mixed x86 control planes and arm workers should build two snapshots."
  }

  assert {
    condition     = imager_image.this["arm"].architecture == "arm"
    error_message = "The arm snapshot should target the arm architecture."
  }

  assert {
    condition     = hcloud_server_network.this["worker-1"].ip == "10.5.0.20"
    error_message = "First worker should get private IP .20."
  }
}

run "bring_your_own_snapshot" {
  command = plan

  variables {
    image_ids = { x86 = "123456789" }
    instances = [
      { name = "controlplane", role = "controlplane", count = 1, server_type = "cx22" },
    ]
  }

  assert {
    condition     = length(imager_image.this) == 0
    error_message = "Supplying an x86 snapshot id should skip building an image."
  }
}

run "invalid_inputs" {
  command = plan

  variables {
    talos_version = "v1.13.6"
    network_cidr  = "not-a-cidr"
    instances = [
      { name = "controlplane", role = "manager", count = 1, server_type = "cx22" },
    ]
  }

  expect_failures = [
    var.talos_version,
    var.network_cidr,
    var.instances,
  ]
}
