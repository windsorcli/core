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
  assert {
    condition     = yamldecode(local.kubelet_csr_approver_patch).cluster.inlineManifests[0].name == "kubelet-csr-approver"
    error_message = "kubelet-csr-approver inlineManifest should be enabled by default"
  }
  assert {
    condition     = strcontains(yamldecode(local.kubelet_csr_approver_patch).cluster.inlineManifests[0].contents, "kind: Deployment")
    error_message = "kubelet-csr-approver inlineManifest should carry the vendored manifest"
  }
}

# Tests a full configuration with all optional variables explicitly set
run "full_configuration" {
  command = plan

  variables {
    cluster_name                = "test-cluster"
    cluster_endpoint            = "https://test.example.com:6443"
    kubernetes_version          = "1.34.1"
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
    enable_kubelet_csr_approver = false
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
    condition     = local.kubelet_csr_approver_patch == ""
    error_message = "kubelet-csr-approver inlineManifest should be omitted when disabled"
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
    kubernetes_version = "1.34.1"
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

# Verifies that an endpoint IP no control plane uses becomes the shared VIP on the given interface
run "vip_inferred_from_endpoint" {
  command = plan

  variables {
    cluster_endpoint = "https://10.0.0.5:6443"
    vip_interface = {
      deviceSelector = { physical = true }
      dhcp           = true
    }
    controlplanes = [
      { endpoint = "10.0.0.10:50000", node = "10.0.0.10" },
      { endpoint = "10.0.0.11:50000", node = "10.0.0.11" },
    ]
  }

  assert {
    condition     = local.vip == "10.0.0.5"
    error_message = "VIP should be the cluster_endpoint host"
  }
  assert {
    condition     = yamldecode(local.vip_patch).machine.network.interfaces[0].vip.ip == "10.0.0.5"
    error_message = "VIP patch should set the interface vip"
  }
  assert {
    condition     = yamldecode(local.vip_patch).machine.network.interfaces[0].deviceSelector.physical == true
    error_message = "VIP patch should keep the interface deviceSelector"
  }
  assert {
    condition     = yamldecode(local.vip_patch).machine.network.interfaces[0].dhcp == true
    error_message = "VIP patch should keep the interface dhcp setting"
  }
}

# Verifies that vip_interface with an endpoint that is a control-plane address fails the plan
run "vip_rejects_controlplane_ip" {
  command = plan

  variables {
    cluster_endpoint = "https://10.0.0.10:6443"
    vip_interface    = { deviceSelector = { physical = true } }
    controlplanes    = [{ endpoint = "10.0.0.10:50000", node = "10.0.0.10" }]
  }

  expect_failures = [terraform_data.endpoint_check]
}

# Verifies that no VIP is configured without vip_interface
run "vip_skipped_without_interface_or_ip" {
  command = plan

  variables {
    cluster_endpoint = "https://10.0.0.5:6443"
    controlplanes    = [{ endpoint = "10.0.0.10:50000", node = "10.0.0.10" }]
  }

  assert {
    condition     = local.vip == ""
    error_message = "No VIP should be configured without vip_interface"
  }
}

# Verifies that vip_interface with a hostname endpoint fails the plan
run "vip_rejects_hostname" {
  command = plan

  variables {
    cluster_endpoint = "https://api.example.com:6443"
    vip_interface    = { deviceSelector = { physical = true } }
    controlplanes    = [{ endpoint = "10.0.0.10:50000", node = "10.0.0.10" }]
  }

  expect_failures = [terraform_data.endpoint_check]
}

# Verifies that no configuration files are generated when context_path is empty,
# preventing unnecessary file creation in the root directory
run "no_config_files" {
  command = plan

  variables {
    context_path       = ""
    cluster_name       = "test-cluster"
    cluster_endpoint   = "https://test.example.com:6443"
    kubernetes_version = "1.34.1"
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


}

# Verifies instance_id flows through to each node's machine module.
run "instance_id_propagates" {
  command = plan

  variables {
    cluster_name       = "test-cluster"
    cluster_endpoint   = "https://test.example.com:6443"
    kubernetes_version = "1.34.1"
    talos_version      = "1.10.1"
    controlplanes = [
      {
        hostname    = "cp1"
        endpoint    = "https://cp1.example.com:6443"
        node        = "192.168.1.10"
        instance_id = "container-abc123"
      }
    ]
    workers = [
      {
        hostname    = "worker1"
        endpoint    = "https://worker1.example.com:6443"
        node        = "192.168.1.20"
        instance_id = "container-def456"
      }
    ]
  }

  assert {
    condition     = module.controlplane_bootstrap.instance_id == "container-abc123"
    error_message = "controlplane_bootstrap should receive the controlplane's instance_id"
  }
  assert {
    condition     = module.workers[0].instance_id == "container-def456"
    error_message = "worker module should receive the worker's instance_id"
  }
}

# Verifies that all input validation rules are enforced simultaneously, ensuring that
# invalid values for kubernetes_version, talos_version, cluster_name,
# cluster_endpoint, and YAML configs are properly caught and reported
run "multiple_invalid_inputs" {
  command = plan
  expect_failures = [
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
    kubernetes_version          = "v1.34"
    talos_version               = "v1.10.1"
    cluster_name                = ""
    cluster_endpoint            = "http://localhost:6443"
    common_config_patches       = "not: valid: yaml: ["
    controlplane_config_patches = "not: valid: yaml: ["
    worker_config_patches       = "not: valid: yaml: ["
    controlplanes = [
      {
        endpoint       = "http://localhost:6443"
        node           = "192.168.1.10"
        config_patches = "not: valid: yaml: ["
      }
    ]
    workers = [
      {
        endpoint       = "http://localhost:6443"
        node           = "192.168.1.20"
        config_patches = "not: valid: yaml: ["
      }
    ]
  }
}

# Verifies that each registry mirror renders as a RegistryMirrorConfig document
run "registry_mirrors_render_documents" {
  command = plan

  variables {
    cluster_name     = "test-cluster"
    cluster_endpoint = "https://test.example.com:6443"
    controlplanes = [
      {
        hostname = "cp1"
        endpoint = "https://cp1.example.com:6443"
        node     = "192.168.1.10"
      }
    ]
    registry_mirrors = {
      "docker.io" = { endpoints = [{ url = "https://package.copia.io/v2/copia/docker.io", override_path = true }], skip_fallback = true }
      "ghcr.io"   = { endpoints = [{ url = "http://ghcr.test:5000" }] }
    }
  }

  assert {
    condition     = length(local.registry_mirror_docs) == 2
    error_message = "One RegistryMirrorConfig document should render per registry"
  }
  assert {
    condition     = yamldecode(local.registry_mirror_docs[0]).kind == "RegistryMirrorConfig" && yamldecode(local.registry_mirror_docs[0]).name == "docker.io"
    error_message = "docker.io should render as a RegistryMirrorConfig document"
  }
  assert {
    condition     = yamldecode(local.registry_mirror_docs[0]).endpoints[0].url == "https://package.copia.io/v2/copia/docker.io" && yamldecode(local.registry_mirror_docs[0]).endpoints[0].overridePath == true
    error_message = "docker.io endpoint should carry its url and overridePath"
  }
  assert {
    condition     = !contains(keys(yamldecode(local.registry_mirror_docs[1]).endpoints[0]), "overridePath")
    error_message = "ghcr.io endpoint should omit overridePath"
  }
  assert {
    condition     = yamldecode(local.registry_mirror_docs[0]).skipFallback == true
    error_message = "docker.io should carry skipFallback"
  }
  assert {
    condition     = !contains(keys(yamldecode(local.registry_mirror_docs[1])), "skipFallback")
    error_message = "ghcr.io should omit skipFallback"
  }
}

# Verifies that each registry credential renders as a RegistryAuthConfig document
run "registry_auths_render_documents" {
  command = plan

  variables {
    cluster_name     = "test-cluster"
    cluster_endpoint = "https://test.example.com:6443"
    controlplanes = [
      {
        hostname = "cp1"
        endpoint = "https://cp1.example.com:6443"
        node     = "192.168.1.10"
      }
    ]
    registry_auths = {
      "mirror.test:5000" = { username = "robot", password = "secret" }
    }
  }

  assert {
    condition     = length(local.registry_auth_docs) == 1
    error_message = "One RegistryAuthConfig document should render per registry"
  }
  assert {
    condition     = yamldecode(local.registry_auth_docs[0]).kind == "RegistryAuthConfig" && yamldecode(local.registry_auth_docs[0]).name == "mirror.test:5000"
    error_message = "mirror.test:5000 should render as a RegistryAuthConfig document"
  }
  assert {
    condition     = yamldecode(local.registry_auth_docs[0]).username == "robot" && yamldecode(local.registry_auth_docs[0]).password == "secret"
    error_message = "RegistryAuthConfig should carry the username and password"
  }
}

# Verifies that no RegistryMirrorConfig documents render by default
run "registry_mirrors_default_empty" {
  command = plan

  variables {
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
    condition     = length(local.registry_mirror_docs) == 0
    error_message = "No RegistryMirrorConfig documents should render without registry_mirrors"
  }
  assert {
    condition     = length(local.registry_auth_docs) == 0
    error_message = "No RegistryAuthConfig documents should render without registry_auths"
  }
}

# Verifies that a mirror without endpoints or with a schemeless url fails validation
run "registry_mirrors_invalid" {
  command = plan

  variables {
    cluster_name     = "test-cluster"
    cluster_endpoint = "https://test.example.com:6443"
    controlplanes = [
      {
        hostname = "cp1"
        endpoint = "https://cp1.example.com:6443"
        node     = "192.168.1.10"
      }
    ]
    registry_mirrors = {
      "docker.io" = { endpoints = [] }
      "ghcr.io"   = { endpoints = [{ url = "ghcr.test:5000" }] }
    }
  }

  expect_failures = [var.registry_mirrors]
}
