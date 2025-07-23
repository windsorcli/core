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
  cluster_name        = "dummy"
  cluster_endpoint    = "https://dummy"
  kubernetes_version  = "dummy"
  talos_version       = "1.10.1"
  talosconfig_path    = "/tmp/dummy-talosconfig"
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
