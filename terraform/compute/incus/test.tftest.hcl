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
    condition     = incus_network.main[0].name == "net-test"
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
# Validates that user-supplied values override defaults for network and instances.
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
    instances = [
      {
        name        = "test-instance"
        image       = "ghcr:ubuntu/22.04"
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
            size      = 10
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

# Verifies that network config merge precedence is correct.
# Tests that enable_dhcp and enable_nat override network_config values (last merge wins),
# while other network_config values are preserved and network_cidr adds ipv4.address.
run "network_config_merge_precedence" {
  command = plan

  variables {
    context_id   = "test"
    network_cidr = "10.25.0.0/24"
    enable_dhcp  = true
    enable_nat   = false
    network_config = {
      "ipv4.dhcp"    = "false"  # Should be overridden by enable_dhcp=true
      "ipv4.nat"     = "true"   # Should be overridden by enable_nat=false
      "ipv4.routes"  = "10.0.0.0/8"  # Should be preserved
      "bridge.mode"  = "fan"    # Should be preserved
    }
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.dhcp"] == "true"
    error_message = "enable_dhcp should override network_config ipv4.dhcp value"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.nat"] == "false"
    error_message = "enable_nat should override network_config ipv4.nat value"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.address"] == "10.25.0.1/24"
    error_message = "network_cidr should add ipv4.address gateway"
  }

  assert {
    condition     = incus_network.main[0].config["ipv4.routes"] == "10.0.0.0/8"
    error_message = "Other network_config values should be preserved"
  }

  assert {
    condition     = incus_network.main[0].config["bridge.mode"] == "fan"
    error_message = "Other network_config values should be preserved"
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
            type = "default"
            size = 10
            path = "/mnt/data"
          },
          {
            name = "backup"
            type = "custom-pool"
            size = 20
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
            size   = 10
            path   = "/mnt/data"
          },
          {
            name   = "bind"
            source = "/host/path"
            size   = 10
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
    terraform_data.ip_validation,
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

# Verifies that IP address octet overflow is detected when count > 1 would increment beyond 255.
# Tests that an instance with count > 1 and explicit IP that would overflow the last octet is rejected.
run "ipv4_octet_overflow_detection" {
  command = plan
  expect_failures = [
    terraform_data.ip_validation,
  ]

  variables {
    context_id   = "test"
    network_cidr = "10.80.0.0/24"
    instances = [
      {
        name  = "overflow-instance"
        count = 10
        image = "ubuntu/22.04"
        ipv4  = "10.80.0.250/24" # This would create IPs: 10.80.0.250 through 10.80.0.259 (last octet 259 > 255)
      }
    ]
  }
}

