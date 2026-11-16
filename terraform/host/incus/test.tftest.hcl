mock_provider "incus" {
  override_data {
    target = data.incus_cluster.main
    values = {
      is_clustered = true
      members = {
        node1 = { status = "Online" }
        node2 = { status = "Online" }
      }
    }
  }
}

variables {
  remote            = "lab"
  storage_pool_name = "nvme"
}

# A cluster gets the pool defined on every member, then created once.
run "creates_pool_on_every_member" {
  command = plan

  assert {
    condition     = toset(keys(incus_storage_pool.member)) == toset(["node1", "node2"])
    error_message = "every cluster member must define the pool"
  }

  assert {
    condition     = incus_storage_pool.member["node2"].target == "node2" && incus_storage_pool.member["node2"].config.source == "nvme/incus"
    error_message = "member pool must target its member with <pool>/incus as source"
  }

  assert {
    condition     = incus_storage_pool.main.name == "nvme" && incus_storage_pool.main.driver == "zfs" && incus_storage_pool.main.target == null
    error_message = "cluster pool must be a zfs pool named nvme with no target"
  }

  assert {
    condition     = length(incus_storage_pool.main.config) == 0
    error_message = "cluster pool must carry no member-specific source"
  }
}

# A single server gets one pool with the dataset as source.
run "creates_pool_on_single_server" {
  command = plan

  override_data {
    target = data.incus_cluster.main
    values = {
      is_clustered = false
      members      = {}
    }
  }

  assert {
    condition     = length(incus_storage_pool.member) == 0
    error_message = "a single server must not get member pools"
  }

  assert {
    condition     = incus_storage_pool.main.config.source == "nvme/incus"
    error_message = "single-server pool must take the dataset as source"
  }
}

# An explicit dataset replaces <pool>/incus.
run "uses_explicit_dataset" {
  command = plan

  variables {
    dataset = "tank/vms"
  }

  assert {
    condition     = incus_storage_pool.member["node1"].config.source == "tank/vms"
    error_message = "member pool must take the explicit dataset as source"
  }
}

run "rejects_malformed_dataset" {
  command = plan

  variables {
    dataset = "/nvme/incus"
  }

  expect_failures = [var.dataset]
}
