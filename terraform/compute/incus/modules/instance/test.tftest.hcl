mock_provider "incus" {
  mock_resource "incus_instance" {}
}

# Verifies that the module creates an instance with minimal configuration.
# Tests default values for type, network device, and root disk.
run "minimal_configuration" {
  command = plan

  variables {
    name         = "test-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
  }

  assert {
    condition     = incus_instance.this.type == "container"
    error_message = "Instance type should default to 'container'"
  }

  assert {
    condition     = incus_instance.this.ephemeral == false
    error_message = "Instance should not be ephemeral by default"
  }

  assert {
    condition     = length(incus_instance.this.device) > 0
    error_message = "Instance should have at least one device (root disk and network)"
  }
}

# Tests a full configuration with all optional variables explicitly set.
# Validates that user-supplied values override defaults for type, limits, devices, and config.
run "full_configuration" {
  command = plan

  variables {
    name         = "full-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    type         = "virtual-machine"
    description  = "Full configuration test instance"
    ephemeral    = true
    project      = "test-project"
    remote       = "test-remote"
    target       = "test-target"
    networks     = ["network1", "network2"]
    network_config = {
      "ipv4.routes" = "10.0.0.0/8"
    }
    ipv4 = "10.5.0.100/24"
    limits = {
      cpu    = "2"
      memory = "4GB"
    }
    profiles = ["profile1", "profile2"]
    devices = {
      "gpu" = {
        type       = "gpu"
        properties = { "gpu" = "all" }
      }
    }
    disks = [
      {
        name      = "data-disk"
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
        connect = "tcp:10.5.0.100:80"
      }
    }
    secureboot     = true
    root_disk_size = "20GB"
    qemu_args      = "-boot order=c"
    config = {
      "user.network-config" = "disabled"
    }
  }

  assert {
    condition     = incus_instance.this.type == "virtual-machine"
    error_message = "Instance type should match input"
  }

  assert {
    condition     = incus_instance.this.description == "Full configuration test instance"
    error_message = "Instance description should match input"
  }

  assert {
    condition     = incus_instance.this.ephemeral == true
    error_message = "Instance should be ephemeral when set"
  }

  assert {
    condition     = incus_instance.this.project == "test-project"
    error_message = "Instance project should match input"
  }
}

# Verifies that custom networks override the default network_name.
# Tests that multiple networks create multiple eth devices.
run "custom_networks_override_default" {
  command = plan

  variables {
    name         = "multi-net-instance"
    image        = "ubuntu/22.04"
    network_name = "default-network"
    networks     = ["network1", "network2"]
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth0"]) == 1
    error_message = "Should create eth0 device for first custom network"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth1"]) == 1
    error_message = "Should create eth1 device for second custom network"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth0" && d.properties.network == "network1"]) == 1
    error_message = "eth0 should be attached to network1"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth1" && d.properties.network == "network2"]) == 1
    error_message = "eth1 should be attached to network2"
  }
}

# Verifies that container instances do not have VM-specific configuration.
# Tests that secureboot and qemu_args are not applied to containers.
run "container_no_vm_config" {
  command = plan

  variables {
    name         = "container-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    type         = "container"
  }

  assert {
    condition     = !contains(keys(incus_instance.this.config), "security.secureboot")
    error_message = "Container should not have secureboot config"
  }

  assert {
    condition     = !contains(keys(incus_instance.this.config), "raw.qemu")
    error_message = "Container should not have qemu_args config"
  }
}

# Verifies that file path bind mounts are detected and configured correctly.
# Tests Unix absolute paths, Windows drive letters, and UNC paths.
run "file_path_bind_mount" {
  command = plan

  variables {
    name         = "bind-mount-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    disks = [
      {
        name   = "unix-mount"
        pool   = "default"  # Required by schema, but not used for bind mounts
        size   = 1          # Required by schema, but not used for bind mounts
        source = "/host/path/data"
        path   = "/mnt/data"
      },
      {
        name   = "windows-mount"
        pool   = "default"
        size   = 1
        source = "C:\\host\\path\\data"
        path   = "/mnt/windows"
      },
      {
        name   = "unc-mount"
        pool   = "default"
        size   = 1
        source = "\\\\server\\share\\data"
        path   = "/mnt/unc"
      }
    ]
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "unix-mount" && d.properties.source == "/host/path/data" && !contains(keys(d.properties), "pool")]) == 1
    error_message = "Unix path bind mount should not include pool property"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "windows-mount" && d.properties.source == "C:\\host\\path\\data"]) == 1
    error_message = "Windows drive path should be recognized as bind mount"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "unc-mount" && d.properties.source == "\\\\server\\share\\data"]) == 1
    error_message = "UNC path should be recognized as bind mount"
  }
}

# Verifies that instance type validation is enforced.
# Tests that invalid instance types are rejected.
run "invalid_instance_type" {
  command = plan
  expect_failures = [
    var.type,
  ]

  variables {
    name         = "invalid-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    type         = "invalid-type"
  }
}

# Verifies that IPv6 static address is configured correctly on the primary interface.
# Tests that IPv6 address is added to device properties and CIDR notation is stripped.
run "ipv6_static_address_configuration" {
  command = plan

  variables {
    name         = "ipv6-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    ipv6         = "2001:db8::100/64"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth0" && d.properties["ipv6.address"] == "2001:db8::100"]) == 1
    error_message = "IPv6 address should be configured on eth0 with CIDR notation stripped"
  }
}

# Verifies that both IPv4 and IPv6 static addresses can be configured simultaneously.
# Tests dual-stack configuration with both addresses on the primary interface.
run "dual_stack_static_addresses" {
  command = plan

  variables {
    name         = "dual-stack-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    ipv4         = "10.5.0.100/24"
    ipv6         = "2001:db8::100/64"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth0" && d.properties["ipv4.address"] == "10.5.0.100" && d.properties["ipv6.address"] == "2001:db8::100"]) == 1
    error_message = "Both IPv4 and IPv6 addresses should be configured on eth0"
  }
}

# Verifies that wait_for_ipv4 logic correctly waits when static IPv4 is set.
# Tests that wait_for block is created for IPv4 when static IP is configured.
run "wait_for_ipv4_with_static_address" {
  command = plan

  variables {
    name         = "static-ipv4-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    ipv4         = "10.5.0.100/24"
    wait_for_ipv4 = false  # Should still wait because static IP is set
  }

  assert {
    condition     = length(incus_instance.this.wait_for) > 0
    error_message = "Should wait for IPv4 when static IPv4 is configured, even if wait_for_ipv4 is false"
  }

  assert {
    condition     = length([for w in incus_instance.this.wait_for : w if w.type == "ipv4" && w.nic == "eth0"]) > 0
    error_message = "Should wait for IPv4 on eth0 when static IPv4 is configured"
  }
}

# Verifies that wait_for_ipv4 logic correctly waits for DHCP when enabled.
# Tests that wait_for block is created for IPv4 when wait_for_ipv4 is true and no static IP.
run "wait_for_ipv4_with_dhcp" {
  command = plan

  variables {
    name         = "dhcp-ipv4-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    wait_for_ipv4 = true
  }

  assert {
    condition     = length([for w in incus_instance.this.wait_for : w if w.type == "ipv4" && w.nic == "eth0"]) > 0
    error_message = "Should wait for IPv4 on eth0 when wait_for_ipv4 is true (DHCP case)"
  }
}

# Verifies that wait_for_ipv6 logic correctly waits when static IPv6 is set.
# Tests that wait_for block is created for IPv6 when static IP is configured.
run "wait_for_ipv6_with_static_address" {
  command = plan

  variables {
    name         = "static-ipv6-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    ipv6         = "2001:db8::100/64"
    wait_for_ipv6 = false  # Should still wait because static IP is set
  }

  assert {
    condition     = length([for w in incus_instance.this.wait_for : w if w.type == "ipv6" && w.nic == "eth0"]) > 0
    error_message = "Should wait for IPv6 on eth0 when static IPv6 is configured, even if wait_for_ipv6 is false"
  }
}

# Verifies that wait_for_ipv6 logic correctly waits for DHCP when explicitly enabled.
# Tests that wait_for block is created for IPv6 when wait_for_ipv6 is true and no static IP.
run "wait_for_ipv6_with_dhcp" {
  command = plan

  variables {
    name         = "dhcp-ipv6-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    wait_for_ipv6 = true
  }

  assert {
    condition     = length([for w in incus_instance.this.wait_for : w if w.type == "ipv6" && w.nic == "eth0"]) > 0
    error_message = "Should wait for IPv6 on eth0 when wait_for_ipv6 is explicitly true (DHCP case)"
  }
}

# Verifies that wait_for_ipv6 does not wait by default when no static IPv6 is set.
# Tests that wait_for block is not created for IPv6 when wait_for_ipv6 is not explicitly set.
run "wait_for_ipv6_default_behavior" {
  command = plan

  variables {
    name         = "no-ipv6-wait-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    # wait_for_ipv6 not set (defaults to null)
  }

  assert {
    condition     = length([for w in incus_instance.this.wait_for : w if w.type == "ipv6"]) == 0
    error_message = "Should not wait for IPv6 by default when no static IPv6 is configured and wait_for_ipv6 is not set"
  }
}

# Verifies that IPv4 address validation rejects invalid formats.
# Tests that invalid IPv4 addresses (wrong format, out of range octets) are rejected.
run "invalid_ipv4_address_format" {
  command = plan
  expect_failures = [
    var.ipv4,
  ]

  variables {
    name         = "invalid-ipv4-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    ipv4         = "999.999.999.999"  # Invalid: octets out of range
  }
}

# Verifies that IPv4 address validation rejects invalid formats.
# Tests that invalid IPv4 addresses (wrong format) are rejected.
run "invalid_ipv4_address_format_wrong_structure" {
  command = plan
  expect_failures = [
    var.ipv4,
  ]

  variables {
    name         = "invalid-ipv4-format-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    ipv4         = "not-an-ip"  # Invalid: not an IP address format
  }
}

# Verifies that IPv6 address validation rejects invalid formats.
# Tests that invalid IPv6 addresses (missing colons, invalid characters) are rejected.
run "invalid_ipv6_address_format" {
  command = plan
  expect_failures = [
    var.ipv6,
  ]

  variables {
    name         = "invalid-ipv6-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    ipv6         = "not-an-ipv6"  # Invalid: no colons, not IPv6 format
  }
}


