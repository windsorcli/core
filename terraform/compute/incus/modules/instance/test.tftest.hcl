mock_provider "incus" {
  mock_resource "incus_instance" {}
}

# Verifies that the module creates an instance with minimal configuration.
# Tests default values for type, network device, and root disk.
run "minimal_configuration" {
  command = plan

  variables {
    name        = "test-instance"
    image       = "ubuntu/22.04"
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
    name        = "multi-net-instance"
    image       = "ubuntu/22.04"
    network_name = "default-network"
    networks    = ["network1", "network2"]
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

# Verifies that static IPv4 address is properly configured on network device.
# Tests that IP is extracted from CIDR notation and security.ipv4_filtering is set.
run "static_ipv4_configuration" {
  command = plan

  variables {
    name        = "static-ip-instance"
    image       = "ubuntu/22.04"
    network_name = "test-network"
    ipv4        = "10.5.0.87/24"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth0" && d.properties["ipv4.address"] == "10.5.0.87"]) == 1
    error_message = "Network device should have static IPv4 address extracted from CIDR"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "eth0" && d.properties["security.ipv4_filtering"] == "true"]) == 1
    error_message = "Network device should have security.ipv4_filtering enabled for static IP"
  }
}

# Verifies that VM-specific configuration is applied correctly.
# Tests secureboot, root disk boot priority, and qemu_args.
run "virtual_machine_configuration" {
  command = plan

  variables {
    name         = "vm-instance"
    image        = "ubuntu/22.04"
    network_name = "test-network"
    type         = "virtual-machine"
    secureboot   = true
    root_disk_size = "30GB"
    qemu_args    = "-boot order=c,menu=off"
  }

  assert {
    condition     = incus_instance.this.config["security.secureboot"] == "true"
    error_message = "VM should have secureboot enabled"
  }

  assert {
    condition     = incus_instance.this.config["raw.qemu"] == "-boot order=c,menu=off"
    error_message = "VM should have qemu_args in config"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "root" && d.properties["boot.priority"] == "10"]) == 1
    error_message = "VM root disk should have boot priority set"
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

# Verifies that disk devices are properly configured for storage volumes.
# Tests pool, source, path, and read_only properties.
run "storage_volume_disk" {
  command = plan

  variables {
    name        = "disk-instance"
    image       = "ubuntu/22.04"
    network_name = "test-network"
    disks = [
      {
        name      = "data"
        pool      = "custom-pool"
        source    = "data-volume"
        path      = "/mnt/data"
        read_only = false
      },
      {
        name      = "backup"
        pool      = "default"
        source    = "backup-volume"
        path      = "/mnt/backup"
        read_only = true
      }
    ]
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "data" && d.properties.pool == "custom-pool"]) == 1
    error_message = "Data disk should use custom pool"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "data" && d.properties.source == "data-volume"]) == 1
    error_message = "Data disk should reference source volume"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "backup" && d.properties.readonly == "true"]) == 1
    error_message = "Backup disk should be read-only"
  }
}

# Verifies that file path bind mounts are detected and configured correctly.
# Tests Unix absolute paths, Windows drive letters, and UNC paths.
run "file_path_bind_mount" {
  command = plan

  variables {
    name        = "bind-mount-instance"
    image       = "ubuntu/22.04"
    network_name = "test-network"
    disks = [
      {
        name   = "unix-mount"
        source = "/host/path/data"
        path   = "/mnt/data"
      },
      {
        name   = "windows-mount"
        source = "C:\\host\\path\\data"
        path   = "/mnt/windows"
      },
      {
        name   = "unc-mount"
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

# Verifies that proxy devices are properly configured for port forwarding.
# Tests listen and connect properties.
run "proxy_devices_configuration" {
  command = plan

  variables {
    name        = "proxy-instance"
    image       = "ubuntu/22.04"
    network_name = "test-network"
    proxy_devices = {
      "http" = {
        listen  = "tcp:0.0.0.0:8080"
        connect = "tcp:10.5.0.100:80"
      }
      "https" = {
        listen  = "tcp:0.0.0.0:8443"
        connect = "tcp:10.5.0.100:443"
      }
    }
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "http" && d.type == "proxy"]) == 1
    error_message = "Should create http proxy device"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "http" && d.properties.listen == "tcp:0.0.0.0:8080"]) == 1
    error_message = "HTTP proxy should have correct listen address"
  }

  assert {
    condition     = length([for d in incus_instance.this.device : d if d.name == "https" && d.properties.connect == "tcp:10.5.0.100:443"]) == 1
    error_message = "HTTPS proxy should have correct connect address"
  }
}

# Verifies that resource limits are properly configured in instance config.
# Tests CPU and memory limits.
run "resource_limits_configuration" {
  command = plan

  variables {
    name        = "limited-instance"
    image       = "ubuntu/22.04"
    network_name = "test-network"
    limits = {
      cpu    = "4"
      memory = "8GB"
    }
  }

  assert {
    condition     = incus_instance.this.config["limits.cpu"] == "4"
    error_message = "CPU limit should be set in config"
  }

  assert {
    condition     = incus_instance.this.config["limits.memory"] == "8GB"
    error_message = "Memory limit should be set in config"
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
    name        = "invalid-instance"
    image       = "ubuntu/22.04"
    network_name = "test-network"
    type        = "invalid-type"
  }
}


