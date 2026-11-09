mock_provider "proxmox" {}

variables {
  nodes                = ["pve"]
  image_datastore_id   = "windsor-images"
  image_datastore_path = "/var/lib/windsor-images"
}

# The module creates the storage.
run "creates_storage" {
  command = plan

  assert {
    condition     = proxmox_storage_directory.images.id == "windsor-images"
    error_message = "storage id must come from image_datastore_id"
  }

  assert {
    condition     = proxmox_storage_directory.images.path == "/var/lib/windsor-images"
    error_message = "storage path must come from image_datastore_path"
  }

  assert {
    condition     = proxmox_storage_directory.images.content == toset(["import"])
    error_message = "storage must hold the import content type only"
  }

  assert {
    condition     = proxmox_storage_directory.images.create_base_path == true
    error_message = "storage must create its base directory"
  }

  assert {
    condition     = proxmox_storage_directory.images.nodes == toset(["pve"])
    error_message = "storage must be available on the nodes input"
  }
}

# The nodes input takes a list.
run "storage_on_every_node" {
  command = plan

  variables {
    nodes = ["pve1", "pve2"]
  }

  assert {
    condition     = proxmox_storage_directory.images.nodes == toset(["pve1", "pve2"])
    error_message = "storage must be available on every node in nodes"
  }
}

run "rejects_empty_nodes" {
  command = plan

  variables {
    nodes = []
  }

  expect_failures = [var.nodes]
}

run "rejects_relative_path" {
  command = plan

  variables {
    image_datastore_path = "windsor-images"
  }

  expect_failures = [var.image_datastore_path]
}
