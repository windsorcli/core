# Verifies that the module creates machine secrets with the correct Talos version
# and generates the necessary configuration files for cluster access using minimal configuration
run "minimal_configuration" {
  command = plan

  variables {
    context_path     = "test"
    cluster_name     = "test-cluster"
    cluster_endpoint = "https://test.example.com:6443"
    controlplanes = [
      {
        hostname = "cp1"
        endpoint = "https://cp1.example.com:6443"
        node     = "192.168.1.10"
      }
    ]
  }

  assert {
    condition     = length(local_sensitive_file.talosconfig) == 1
    error_message = "Talos config file should be generated"
  }

  assert {
    condition     = length(local_sensitive_file.kubeconfig) == 1
    error_message = "Kubeconfig file should be generated"
  }

  assert {
    condition     = module.controlplane_bootstrap.node == "192.168.1.10"
    error_message = "controlplane_bootstrap node should match input"
  }
  assert {
    condition     = module.controlplane_bootstrap.endpoint == "https://cp1.example.com:6443"
    error_message = "controlplane_bootstrap endpoint should match input"
  }
  assert {
    condition     = length(module.controlplanes) == 0
    error_message = "No additional controlplanes should be created in minimal config"
  }
}

# Tests a full configuration with all optional variables explicitly set
run "full_configuration" {
  command = plan

  variables {
    cluster_name                = "test-cluster"
    cluster_endpoint            = "https://test.example.com:6443"
    kubernetes_version          = "1.33.0"
    talos_version               = "1.10.1"
    common_config_patches       = <<-EOT
      machine:
        network:
          nameservers:
            - 8.8.8.8
    EOT
    controlplane_config_patches = <<-EOT
      machine:
        controlplane:
          extraArgs:
            - "--enable-admission-plugins=NodeRestriction"
    EOT
    worker_config_patches       = <<-EOT
      machine:
        kubelet:
          extraArgs:
            - "--max-pods=110"
    EOT
    controlplanes = [
      {
        hostname = "cp1"
        endpoint = "https://cp1.example.com:6443"
        node     = "192.168.1.10"
        disk_selector = {
          name = "/dev/sda"
        }
        wipe_disk = true
      }
    ]
    workers = [
      {
        hostname = "worker1"
        endpoint = "https://worker1.example.com:6443"
        node     = "192.168.1.20"
        disk_selector = {
          name = "/dev/sdb"
        }
        wipe_disk = false
      }
    ]
  }

  assert {
    condition     = module.controlplane_bootstrap.node == "192.168.1.10"
    error_message = "controlplane_bootstrap node should match input"
  }
  assert {
    condition     = module.controlplane_bootstrap.endpoint == "https://cp1.example.com:6443"
    error_message = "controlplane_bootstrap endpoint should match input"
  }
  assert {
    condition     = length(module.controlplanes) == 0
    error_message = "No additional controlplanes should be created in this config"
  }
  assert {
    condition     = length(module.workers) == 1
    error_message = "Should create one worker"
  }
  assert {
    condition     = module.workers[0].node == "192.168.1.20"
    error_message = "Worker node should match input"
  }
  assert {
    condition     = module.workers[0].endpoint == "https://worker1.example.com:6443"
    error_message = "Worker endpoint should match input"
  }
}

# Tests the creation of a multi-node cluster with both control planes and workers,
# ensuring proper configuration for each node type
run "multi_node_configuration" {
  command = plan

  variables {
    cluster_name       = "test-cluster"
    cluster_endpoint   = "https://test.example.com:6443"
    kubernetes_version = "1.33.0"
    talos_version      = "1.10.1"
    controlplanes = [
      {
        hostname = "cp1"
        endpoint = "https://cp1.example.com:6443"
        node     = "192.168.1.10"
      },
      {
        hostname = "cp2"
        endpoint = "https://cp2.example.com:6443"
        node     = "192.168.1.11"
      }
    ]
    workers = [
      {
        hostname = "worker1"
        endpoint = "https://worker1.example.com:6443"
        node     = "192.168.1.20"
      }
    ]
  }

  assert {
    condition     = module.controlplane_bootstrap.node == "192.168.1.10"
    error_message = "controlplane_bootstrap node should match first input"
  }
  assert {
    condition     = module.controlplane_bootstrap.endpoint == "https://cp1.example.com:6443"
    error_message = "controlplane_bootstrap endpoint should match first input"
  }
  assert {
    condition     = length(module.controlplanes) == 1
    error_message = "Should create one additional control plane"
  }
  assert {
    condition     = module.controlplanes[0].node == "192.168.1.11"
    error_message = "Second controlplane node should match input"
  }
  assert {
    condition     = module.controlplanes[0].endpoint == "https://cp2.example.com:6443"
    error_message = "Second controlplane endpoint should match input"
  }
  assert {
    condition     = length(module.workers) == 1
    error_message = "Should create one worker"
  }
  assert {
    condition     = module.workers[0].node == "192.168.1.20"
    error_message = "Worker node should match input"
  }
  assert {
    condition     = module.workers[0].endpoint == "https://worker1.example.com:6443"
    error_message = "Worker endpoint should match input"
  }
}

# Verifies that no configuration files are generated when context_path is empty,
# preventing unnecessary file creation in the root directory
run "no_config_files" {
  command = plan

  variables {
    context_path       = ""
    cluster_name       = "test-cluster"
    cluster_endpoint   = "https://test.example.com:6443"
    kubernetes_version = "1.33.0"
    talos_version      = "1.10.1"
    controlplanes = [
      {
        hostname = "cp1"
        endpoint = "https://cp1.example.com:6443"
        node     = "192.168.1.10"
      }
    ]
    workers = []
  }

  assert {
    condition     = length(local_sensitive_file.talosconfig) == 0
    error_message = "No Talos config file should be generated without context path"
  }

  assert {
    condition     = length(local_sensitive_file.kubeconfig) == 0
    error_message = "No Kubeconfig file should be generated without context path"
  }
}

# Verifies that all input validation rules are enforced simultaneously, ensuring that
# invalid values for os_type, kubernetes_version, talos_version, cluster_name,
# cluster_endpoint, and YAML configs are properly caught and reported
run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
    var.os_type,
    var.kubernetes_version,
    var.talos_version,
    var.cluster_name,
    var.cluster_endpoint,
    var.common_config_patches,
    var.controlplane_config_patches,
    var.worker_config_patches,
    var.controlplanes,
    var.workers,
  ]
  variables {
    os_type = "macos"
    kubernetes_version = "v1.33"
    talos_version = "v1.10.1"
    cluster_name = ""
    cluster_endpoint = "http://localhost:6443"
    common_config_patches = "not: valid: yaml: ["
    controlplane_config_patches = "not: valid: yaml: ["
    worker_config_patches = "not: valid: yaml: ["
    controlplanes = [
      {
        endpoint = "http://localhost:6443"
        node     = "192.168.1.10"
        config_patches = "not: valid: yaml: ["
      }
    ]
    workers = [
      {
        endpoint = "http://localhost:6443"
        node     = "192.168.1.20"
        config_patches = "not: valid: yaml: ["
      }
    ]
  }
}
