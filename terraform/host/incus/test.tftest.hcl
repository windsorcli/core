mock_provider "incus" {}

variables {
  remote = "lab"
  members = {
    node1 = { storage_source = "nvme/incus", network_parent = "enp1s0" }
    node2 = { storage_source = "nvme/incus", network_parent = "eno1" }
  }
}

# Minimal input creates the pool on every member and no network.
run "creates_pool_per_member" {
  command = plan

  variables {
    members = {
      node1 = { storage_source = "nvme/incus" }
    }
  }

  assert {
    condition     = incus_storage_pool.member["node1"].target == "node1" && incus_storage_pool.member["node1"].config.source == "nvme/incus"
    error_message = "member pool must target its member with its storage_source"
  }

  assert {
    condition     = incus_storage_pool.main.name == "default" && incus_storage_pool.main.driver == "zfs" && incus_storage_pool.main.target == null
    error_message = "cluster pool must default to a zfs pool named default with no target"
  }

  assert {
    condition     = length(incus_network.main) == 0 && length(incus_network.member) == 0
    error_message = "no network without network_name"
  }

  assert {
    condition     = length(incus_server.member) == 0 && length(incus_storage_volume.daemon) == 0
    error_message = "server config must stay unmanaged without daemon_storage_pool"
  }
}

# network_name creates a physical network with each member's parent.
run "creates_physical_network" {
  command = plan

  variables {
    network_name = "lan"
  }

  assert {
    condition     = incus_network.member["node1"].config.parent == "enp1s0" && incus_network.member["node2"].config.parent == "eno1"
    error_message = "member network must take its member's network_parent"
  }

  assert {
    condition     = incus_network.member["node2"].target == "node2" && incus_network.member["node2"].type == "physical"
    error_message = "member network must be physical and target its member"
  }

  assert {
    condition     = incus_network.main[0].name == "lan" && incus_network.main[0].type == "physical" && incus_network.main[0].target == null
    error_message = "cluster network must be physical with no target"
  }

  assert {
    condition     = output.network == "lan"
    error_message = "network output must name the network"
  }
}

# daemon_storage_pool creates three volumes per member and points the server keys at them.
run "points_daemon_storage_at_volumes" {
  command = plan

  variables {
    daemon_storage_pool = "local"
  }

  assert {
    condition     = length(incus_storage_volume.daemon) == 6
    error_message = "each member must get images, backups, and logs volumes"
  }

  assert {
    condition     = incus_storage_volume.daemon["node2/logs"].target == "node2" && incus_storage_volume.daemon["node2/logs"].pool == "local"
    error_message = "daemon volume must sit on its member in daemon_storage_pool"
  }

  assert {
    condition = incus_server.member["node1"].target == "node1" && incus_server.member["node1"].config == tomap({
      "storage.images_volume"  = "local/images"
      "storage.backups_volume" = "local/backups"
      "storage.logs_volume"    = "local/logs"
    })
    error_message = "server config must point each key at its member volume"
  }
}

# A certificate that lists projects is restricted to them.
run "restricts_project_certificates" {
  command = plan

  variables {
    projects = {
      home = { description = "home context" }
    }
    certificates = {
      admin = { certificate = "-----BEGIN CERTIFICATE-----\nA\n-----END CERTIFICATE-----" }
      ci    = { certificate = "-----BEGIN CERTIFICATE-----\nB\n-----END CERTIFICATE-----", projects = ["home"] }
    }
  }

  assert {
    condition     = incus_project.main["home"].name == "home" && output.projects == tolist(["home"])
    error_message = "project must take its map key as name"
  }

  assert {
    condition     = incus_certificate.main["admin"].restricted == false && incus_certificate.main["admin"].type == "client"
    error_message = "certificate with no projects must be an unrestricted client certificate"
  }

  assert {
    condition     = incus_certificate.main["ci"].restricted == true && tolist(incus_certificate.main["ci"].projects) == tolist(["home"])
    error_message = "certificate with projects must be restricted to them"
  }
}

run "rejects_empty_members" {
  command = plan

  variables {
    members = {}
  }

  expect_failures = [var.members]
}

run "rejects_network_without_parent" {
  command = plan

  variables {
    network_name = "lan"
    members = {
      node1 = { storage_source = "nvme/incus" }
    }
  }

  expect_failures = [var.network_name]
}

run "rejects_default_project" {
  command = plan

  variables {
    projects = { default = {} }
  }

  expect_failures = [var.projects]
}

run "rejects_non_pem_certificate" {
  command = plan

  variables {
    certificates = { admin = { certificate = "not a certificate" } }
  }

  expect_failures = [var.certificates]
}
