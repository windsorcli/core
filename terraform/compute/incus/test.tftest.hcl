mock_provider "incus" {
  mock_resource "incus_network" {}
  mock_resource "incus_image" {}
  mock_resource "incus_storage_volume" {}
}

mock_provider "null" {
  mock_resource "null_resource" {}
}

# Verifies that the module creates a network and handles instances with minimal configuration.
# Tests default values for network naming, DHCP, NAT, and instance creation.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = length(incus_network.main) == 1
    error_message = "Network should be created by default"
  }

  assert {
    condition     = incus_network.main[0].name == "network-test"
    error_message = "Network name should follow default naming convention with context_id"
  }

  assert {
    condition     = incus_network.main[0].type == "bridge"
    error_message = "Network type should default to 'bridge'"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.dhcp"] == "true"
    error_message = "DHCP should be enabled by default"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.nat"] == "true"
    error_message = "NAT should be enabled by default"
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values override defaults for network, images, and instances.
run "full_configuration" {
  command = plan

  variables {
    context_id          = "test"
    network_name        = "custom-network"
    create_network      = true
    network_description = "Custom network description"
    network_type        = "bridge"
    network_cidr        = "10.10.0.0/24"
    enable_dhcp         = false
    enable_nat          = false
    network_config = {
      "ipv4.routes" = "10.0.0.0/8"
    }
    images = [
      {
        alias  = "test-image"
        remote = "ghcr"
        image  = "ubuntu/22.04"
      }
    ]
    instances = [
      {
        name        = "test-instance"
        image       = "test-image"
        type        = "container"
        description = "Test instance"
        ephemeral   = true
        target      = "node1"
        networks    = ["network1", "network2"]
        network_config = {
          "ipv4.routes" = "10.0.0.0/8"
        }
        ipv4 = "10.10.0.100/24"
        limits = {
          cpu    = "2"
          memory = "4GB"
        }
        profiles = ["profile1"]
        devices = {
          "gpu" = {
            type       = "gpu"
            properties = { "gpu" = "all" }
          }
        }
        disks = [
          {
            name      = "data"
            pool      = "default"
            source    = "data-volume"
            path      = "/mnt/data"
            read_only = false
          }
        ]
        proxy_devices = {
          "http" = {
            listen  = "tcp:0.0.0.0:8080"
            connect = "tcp:10.10.0.100:80"
          }
        }
        secureboot     = false
        root_disk_size = "20GB"
        qemu_args      = "-boot order=c"
        config = {
          "user.custom" = "value"
        }
      }
    ]
    project = "test-project"
    remote  = "test-remote"
  }

  assert {
    condition     = incus_network.main[0].name == "custom-network"
    error_message = "Network name should match input"
  }

  assert {
    condition     = incus_network.main[0].description == "Custom network description"
    error_message = "Network description should match input"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.dhcp"] == "false"
    error_message = "DHCP should be disabled when set"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.nat"] == "false"
    error_message = "NAT should be disabled when set"
  }

  assert {
    condition     = length(module.instances) == 1
    error_message = "Should create one instance"
  }
}

# Verifies that network is not created when create_network is false.
# Tests that network_name can reference an existing network.
run "no_network_creation" {
  command = plan

  variables {
    context_id     = "test"
    create_network = false
    network_name   = "existing-network"
  }

  assert {
    condition     = length(incus_network.main) == 0
    error_message = "Network should not be created when create_network is false"
  }

  assert {
    condition     = local.network_name == "existing-network"
    error_message = "Network name should use provided value when network is not created"
  }
}

# Verifies that network CIDR is properly configured when provided.
# Tests that gateway IP and prefix length are calculated correctly.
run "network_cidr_configuration" {
  command = plan

  variables {
    context_id   = "test"
    network_cidr = "10.20.0.0/24"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.address"] == "10.20.0.1/24"
    error_message = "Network gateway should be first IP in CIDR"
  }
}

# Verifies that instance expansion works correctly with count > 1.
# Tests that instances are named with -0, -1 suffixes and IPs are incremented.
run "instance_expansion_with_count" {
  command = plan

  variables {
    context_id   = "test"
    network_cidr = "10.30.0.0/24"
    instances = [
      {
        name  = "pool-instance"
        count = 3
        image = "ubuntu/22.04"
        ipv4  = "10.30.0.10/24"
      }
    ]
  }

  assert {
    condition     = length(module.instances) == 3
    error_message = "Should create 3 instances when count is 3"
  }

  assert {
    condition     = length([for k, v in module.instances : k if k == "pool-instance-0"]) == 1
    error_message = "First instance should be named pool-instance-0"
  }

  assert {
    condition     = length([for k, v in module.instances : k if k == "pool-instance-1"]) == 1
    error_message = "Second instance should be named pool-instance-1"
  }

  assert {
    condition     = length([for k, v in module.instances : k if k == "pool-instance-2"]) == 1
    error_message = "Third instance should be named pool-instance-2"
  }
}

# Verifies that storage volumes are created for disks with size but no source.
# Tests that volume names follow the naming pattern instance-name-disk-name.
run "storage_volume_creation" {
  command = plan

  variables {
    context_id = "test"
    instances = [
      {
        name  = "volume-instance"
        image = "ubuntu/22.04"
        disks = [
          {
            name = "data"
            pool = "default"
            size = "10GB"
            path = "/mnt/data"
          },
          {
            name = "backup"
            pool = "custom-pool"
            size = "20GB"
            path = "/mnt/backup"
          }
        ]
      }
    ]
  }

  assert {
    condition     = length(incus_storage_volume.disks) == 2
    error_message = "Should create 2 storage volumes"
  }

  assert {
    condition     = length([for k, v in incus_storage_volume.disks : k if k == "volume-instance-data"]) == 1
    error_message = "Should create volume for data disk"
  }

  assert {
    condition     = incus_storage_volume.disks["volume-instance-data"].name == "volume-instance-data"
    error_message = "Volume name should follow instance-name-disk-name pattern"
  }

  assert {
    condition     = incus_storage_volume.disks["volume-instance-backup"].pool == "custom-pool"
    error_message = "Volume should use specified pool"
  }
}

# Verifies that storage volumes are not created when source is provided.
# Tests that existing volumes or bind mounts do not trigger volume creation.
run "no_storage_volume_when_source_provided" {
  command = plan

  variables {
    context_id = "test"
    instances = [
      {
        name  = "existing-volume-instance"
        image = "ubuntu/22.04"
        disks = [
          {
            name   = "data"
            source = "existing-volume"
            path   = "/mnt/data"
          },
          {
            name   = "bind"
            source = "/host/path"
            path   = "/mnt/bind"
          }
        ]
      }
    ]
  }

  assert {
    condition     = length(incus_storage_volume.disks) == 0
    error_message = "Should not create volumes when source is provided"
  }
}

# Verifies that network type validation is enforced.
# Tests that invalid network types are rejected.
run "invalid_network_type" {
  command = plan
  expect_failures = [
    var.network_type,
  ]

  variables {
    context_id   = "test"
    network_type = "invalid-type"
  }
}

# Verifies that instance type validation is enforced.
# Tests that invalid instance types are rejected.
run "invalid_instance_type" {
  command = plan
  expect_failures = [
    var.instances,
  ]

  variables {
    context_id = "test"
    instances = [
      {
        name  = "invalid-instance"
        image = "ubuntu/22.04"
        type  = "invalid-type"
      }
    ]
  }
}

# Verifies that IP address conflicts are detected when count > 1 increments IPs.
# Tests that an instance with count > 1 and explicit IP cannot conflict with another instance's IP.
run "ipv4_conflict_detection" {
  command = plan
  expect_failures = [
    check.ipv4_conflicts,
  ]

  variables {
    context_id   = "test"
    network_cidr = "10.70.0.0/24"
    instances = [
      {
        name  = "pool-instance"
        count = 3
        image = "ubuntu/22.04"
        ipv4  = "10.70.0.10/24" # This creates IPs: 10.70.0.10, 10.70.0.11, 10.70.0.12
      },
      {
        name  = "conflicting-instance"
        image = "ubuntu/22.04"
        ipv4  = "10.70.0.11/24" # This conflicts with pool-instance-1's IP
      }
    ]
  }
}

