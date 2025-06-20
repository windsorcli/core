mock_provider "talos" {
  mock_resource "talos_machine_configuration" {}
  mock_resource "talos_machine_configuration_apply" {}
  mock_resource "talos_machine_bootstrap" {}
}

mock_provider "null" {
  mock_resource "null_resource" {}
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
  cluster_name       = "dummy"
  cluster_endpoint   = "https://dummy"
  kubernetes_version = "dummy"
  talos_version      = "1.10.1"
  platform           = "metal"
}

run "machine_config_patch_with_disk_and_hostname" {
  command = plan
  
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
    condition     = strcontains(local.machine_config_patch, "factory.talos.dev/metal-installer:v1.10.1")
    error_message = "Should include versioned installer image URL"
  }
  assert {
    condition     = strcontains(local.machine_config_patch, "- \"image\": \"test-extension\"")
    error_message = "Should include extension test-extension"
  }
}

run "machine_config_patch_without_disk" {
  command = plan
  
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
  command = plan
  
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
  command = plan
  
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

run "custom_installer_image" {
  command = plan

  variables {
    machine_type       = "controlplane"
    endpoint           = "172.20.0.10"
    node               = "172.20.0.10"
    cluster_name       = "test-cluster"
    cluster_endpoint   = "https://172.20.0.10:6443"
    kubernetes_version = "1.31.0"
    talos_version      = "1.8.2"
    platform           = "metal"
    installer_image    = "factory.talos.dev/metal-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v1.8.2"
  }

  # Validate that the installer_image local uses the custom image when provided
  assert {
    condition     = local.installer_image == "factory.talos.dev/metal-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v1.8.2"
    error_message = "installer_image local should use the custom image when installer_image variable is provided. Got: ${local.installer_image}"
  }
}
