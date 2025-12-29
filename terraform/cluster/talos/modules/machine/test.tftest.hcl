mock_provider "talos" {
  mock_resource "talos_machine_configuration" {}
  mock_resource "talos_machine_configuration_apply" {}
  mock_resource "talos_machine_bootstrap" {}
  mock_resource "talos_cluster_kubeconfig" {}
}

mock_provider "null" {
  mock_resource "null_resource" {}
}

mock_provider "local" {
  mock_resource "local_sensitive_file" {}
}

variables {
  machine_type = "controlplane"
  endpoint     = "dummy"
  node         = "dummy"
  client_configuration = {
    ca_certificate     = "dummy"
    client_certificate = "dummy"
    client_key         = "dummy"
  }
  machine_secrets = {
    certs = {
      etcd = {
        cert = "dummy"
        key  = "dummy"
      }
      k8s = {
        cert = "dummy"
        key  = "dummy"
      }
      k8s_aggregator = {
        cert = "dummy"
        key  = "dummy"
      }
      k8s_serviceaccount = {
        key = "dummy"
      }
      os = {
        cert = "dummy"
        key  = "dummy"
      }
    }
    cluster = {
      id     = "dummy"
      secret = "dummy"
    }
    secrets = {
      bootstrap_token             = "dummy"
      secretbox_encryption_secret = "dummy"
    }
    trustdinfo = {
      token = "dummy"
    }
  }
  cluster_name        = "dummy"
  cluster_endpoint    = "https://dummy"
  kubernetes_version  = "dummy"
  talos_version       = "1.10.1"
  talosconfig_path    = "/tmp/dummy-talosconfig"
  kubeconfig_path     = ""
  enable_health_check = false
}

run "machine_config_patch_with_disk_and_hostname" {
  variables {
    disk_selector = {
      busPath  = ""
      modalias = ""
      model    = ""
      name     = "/dev/sda"
      serial   = ""
      size     = "0"
      type     = ""
      uuid     = ""
      wwid     = ""
    }
    wipe_disk         = true
    hostname          = "test-node"
    extra_kernel_args = ["console=tty0"]
    image             = "test-image"
    extensions        = [{ image = "test-extension" }]
  }
  assert {
    condition     = strcontains(local.machine_config_patch, "\"name\": \"/dev/sda\"")
    error_message = "Should include disk name /dev/sda"
  }
  assert {
    condition     = strcontains(local.machine_config_patch, "\"hostname\": \"test-node\"")
    error_message = "Should include hostname test-node"
  }
  assert {
    condition     = strcontains(local.machine_config_patch, "\"extraKernelArgs\":\n    - \"console=tty0\"")
    error_message = "Should include extra kernel arg console=tty0"
  }
  assert {
    condition     = strcontains(local.machine_config_patch, "\"image\": \"test-image\"")
    error_message = "Should include image test-image"
  }
  assert {
    condition     = strcontains(local.machine_config_patch, "- \"image\": \"test-extension\"")
    error_message = "Should include extension test-extension"
  }
}

run "machine_config_patch_without_disk" {
  variables {
    disk_selector = null
    hostname      = "test-node"
  }
  assert {
    condition     = !can(regex("diskSelector", local.machine_config_patch))
    error_message = "Should not include diskSelector block"
  }
  assert {
    condition     = can(regex("hostname", local.machine_config_patch))
    error_message = "Should include hostname block"
  }
}

run "machine_config_patch_without_hostname" {
  variables {
    disk_selector = {
      busPath  = ""
      modalias = ""
      model    = ""
      name     = "/dev/sda"
      serial   = ""
      size     = "0"
      type     = ""
      uuid     = ""
      wwid     = ""
    }
    hostname = null
  }
  assert {
    condition     = can(regex("diskSelector", local.machine_config_patch))
    error_message = "Should include diskSelector block"
  }
  assert {
    condition     = !can(regex("hostname", local.machine_config_patch))
    error_message = "Should not include hostname block"
  }
}

run "config_patches_includes_extra" {
  variables {
    disk_selector = null
    hostname      = "test-node"
    config_patches = [
      <<-EOT
      machine:
        network:
          nameservers:
            - 8.8.8.8
      EOT
    ]
  }
  assert {
    condition     = length(local.config_patches) == 2
    error_message = "Should include both machine_config_patch and extra patch"
  }
  assert {
    condition     = strcontains(local.config_patches[1], "- 8.8.8.8")
    error_message = "Should include nameservers in extra patch"
  }
}

run "bootstrap_mode_generates_kubeconfig" {
  variables {
    bootstrap       = true
    kubeconfig_path = "/tmp/test-kubeconfig"
    disk_selector   = null
    hostname        = "test-node"
  }

  assert {
    condition     = length(talos_cluster_kubeconfig.this) == 1
    error_message = "Should create kubeconfig resource when bootstrap is true"
  }

  assert {
    condition     = length(local_sensitive_file.kubeconfig) == 1
    error_message = "Should create kubeconfig file when bootstrap is true and path is provided"
  }

  assert {
    condition     = local_sensitive_file.kubeconfig[0].filename == "/tmp/test-kubeconfig"
    error_message = "Should write kubeconfig to specified path"
  }
}

run "non_bootstrap_mode_no_kubeconfig" {
  variables {
    bootstrap       = false
    kubeconfig_path = "/tmp/test-kubeconfig"
    disk_selector   = null
    hostname        = "test-node"
  }

  assert {
    condition     = length(talos_cluster_kubeconfig.this) == 0
    error_message = "Should not create kubeconfig resource when bootstrap is false"
  }

  assert {
    condition     = length(local_sensitive_file.kubeconfig) == 0
    error_message = "Should not create kubeconfig file when bootstrap is false"
  }
}

run "bootstrap_mode_empty_kubeconfig_path" {
  variables {
    bootstrap       = true
    kubeconfig_path = ""
    disk_selector   = null
    hostname        = "test-node"
  }

  assert {
    condition     = length(talos_cluster_kubeconfig.this) == 1
    error_message = "Should create kubeconfig resource when bootstrap is true"
  }

  assert {
    condition     = length(local_sensitive_file.kubeconfig) == 0
    error_message = "Should not create kubeconfig file when path is empty"
  }
}

run "health_check_command_bootstrap_mode" {
  variables {
    bootstrap     = true
    hostname      = "test-node"
    node          = "192.168.1.10"
    endpoint      = "192.168.1.10:50000"
    disk_selector = null
  }

  assert {
    condition     = strcontains(local.health_check_command, "--k8s-endpoint")
    error_message = "Should include --k8s-endpoint flag during bootstrap"
  }

  assert {
    condition     = strcontains(local.health_check_command, "--skip-services dashboard")
    error_message = "Should include --skip-services dashboard flag to skip dashboard health check"
  }

  assert {
    condition     = strcontains(local.health_check_command, "192.168.1.10")
    error_message = "Should use IP address (var.node when it's an IP, otherwise var.endpoint) instead of hostname for health check to avoid DNS resolution issues"
  }
}

run "health_check_command_non_bootstrap_mode" {
  variables {
    bootstrap     = false
    hostname      = "test-node"
    node          = "192.168.1.20"
    endpoint      = "192.168.1.20:50000"
    disk_selector = null
  }

  assert {
    condition     = !strcontains(local.health_check_command, "--k8s-endpoint")
    error_message = "Should not include --k8s-endpoint flag after bootstrap"
  }

  assert {
    condition     = strcontains(local.health_check_command, "--skip-services dashboard")
    error_message = "Should include --skip-services dashboard flag to skip dashboard health check"
  }

  assert {
    condition     = strcontains(local.health_check_command, "192.168.1.20")
    error_message = "Should use IP address (var.node when it's an IP, otherwise var.endpoint) instead of hostname for health check to avoid DNS resolution issues"
  }
}

run "health_check_command_without_hostname" {
  variables {
    bootstrap     = true
    hostname      = ""
    endpoint      = "dummy:50000"
    disk_selector = null
  }

  assert {
    condition     = strcontains(local.health_check_command, "dummy")
    error_message = "Should use node address when hostname is empty"
  }
}

run "health_check_command_with_hostname_as_node" {
  variables {
    bootstrap     = false
    hostname      = "test-node"
    node          = "test-node"          # Hostname instead of IP
    endpoint      = "192.168.1.30:50000" # Endpoint is always IP
    disk_selector = null
  }

  assert {
    condition     = strcontains(local.health_check_command, "192.168.1.30")
    error_message = "Should use endpoint IP address when node is a hostname to avoid DNS resolution issues"
  }

  assert {
    condition     = !strcontains(local.health_check_command, "test-node")
    error_message = "Should not use hostname in health check command"
  }
}
