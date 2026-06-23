mock_provider "vsphere" {
  mock_data "vsphere_datacenter" {
    defaults = {
      id = "datacenter-01"
    }
  }
  mock_data "vsphere_datastore" {
    defaults = {
      id = "datastore-01"
    }
  }
  mock_data "vsphere_compute_cluster" {
    defaults = {
      id               = "cluster-01"
      resource_pool_id = "pool-root"
    }
  }
  mock_data "vsphere_resource_pool" {
    defaults = {
      id = "pool-named"
    }
  }
  mock_data "vsphere_network" {
    defaults = {
      id = "network-01"
    }
  }
  mock_resource "vsphere_virtual_machine" {
    defaults = {
      guest_ip_addresses = []
      power_state        = "poweredOn"
    }
  }
}

mock_provider "talos" {
  mock_resource "talos_machine_secrets" {}
  mock_data "talos_machine_configuration" {
    defaults = {
      machine_configuration = "# mock talos config"
    }
  }
}

# Top-level variables shared across all runs. Required vSphere inventory fields
# plus the two Talos fields that have no defaults. Individual runs add or
# override as needed.
variables {
  context_id       = "test"
  datacenter       = "dc-prod"
  cluster          = "cluster-01"
  datastore        = "datastore-01"
  network          = "VM Network"
  cluster_endpoint = "https://10.5.0.10:6443"
  talos_version    = "1.10.3"
}

# No instances and no images: confirms the module produces no VMs and no
# machineconfig data sources, while always creating talos_machine_secrets.
run "empty_module" {
  command = plan

  assert {
    condition     = length(vsphere_virtual_machine.instances) == 0
    error_message = "No VMs expected when instances list is empty"
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 0
    error_message = "No controlplane machineconfigs expected with empty instances"
  }

  assert {
    condition     = length(data.talos_machine_configuration.worker) == 0
    error_message = "No worker machineconfigs expected with empty instances"
  }
}

# Single controlplane from OVA: verifies CPU propagation, GiB→MiB memory
# conversion, vmxnet3 NIC type, guestinfo extra_config delivery, and OVF
# deploy block engagement.
run "controlplane_from_ova" {
  command = plan

  variables {
    images = {
      talos = {
        url             = "https://factory.talos.dev/image/903b2da78f99adef03cbbd4df6714563823f63218508800751560d3bc3557e40/v1.10.3/vmware-amd64.ova"
        keep_on_destroy = true
      }
    }
    instances = [
      {
        name           = "controlplane"
        role           = "controlplane"
        count          = 1
        image          = "talos"
        cpu            = 4
        memory         = 8
        root_disk_size = 30
        ipv4           = "10.5.0.10"
        notes          = "Talos control plane node"
      }
    ]
  }

  assert {
    condition     = length(vsphere_virtual_machine.instances) == 1
    error_message = "Single controlplane instance should produce one VM"
  }

  assert {
    condition     = vsphere_virtual_machine.instances["controlplane"].name == "controlplane"
    error_message = "VM name should match instance name when count=1"
  }

  assert {
    condition     = vsphere_virtual_machine.instances["controlplane"].num_cpus == 4
    error_message = "num_cpus should propagate from instance.cpu"
  }

  assert {
    condition     = vsphere_virtual_machine.instances["controlplane"].memory == 8 * 1024
    error_message = "memory should be converted from GiB to MiB (8 * 1024 = 8192)"
  }

  assert {
    condition     = vsphere_virtual_machine.instances["controlplane"].annotation == "Talos control plane node"
    error_message = "annotation should carry the instance notes"
  }

  assert {
    condition     = vsphere_virtual_machine.instances["controlplane"].network_interface[0].adapter_type == "vmxnet3"
    error_message = "NIC adapter should be vmxnet3 for vSphere performance compatibility"
  }

  assert {
    condition     = length(vsphere_virtual_machine.instances["controlplane"].ovf_deploy) == 1
    error_message = "OVF deploy block should fire when instance references a valid image URL"
  }

  # extra_config values derived from talos_machine_configuration (itself deferred
  # because machine_secrets is a computed resource attribute) are (known after
  # apply) during plan. Check key presence via contains(keys()) instead.
  assert {
    condition     = contains(keys(vsphere_virtual_machine.instances["controlplane"].extra_config), "guestinfo.talos.config")
    error_message = "Controlplane VM extra_config should include guestinfo.talos.config"
  }

  assert {
    condition     = contains(keys(vsphere_virtual_machine.instances["controlplane"].extra_config), "guestinfo.talos.config.base64")
    error_message = "Controlplane VM extra_config should include guestinfo.talos.config.base64"
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 1
    error_message = "One controlplane machineconfig data source should be generated"
  }

  assert {
    condition     = length(data.talos_machine_configuration.worker) == 0
    error_message = "No worker machineconfig data sources for a controlplane instance"
  }
}

# Worker role: confirms worker machineconfig data source is created (not
# controlplane) and guestinfo is delivered to the VM.
run "worker_role" {
  command = plan

  variables {
    images = {
      talos = {
        url = "https://factory.talos.dev/image/903b2da78f99adef03cbbd4df6714563823f63218508800751560d3bc3557e40/v1.10.3/vmware-amd64.ova"
      }
    }
    instances = [
      {
        name           = "worker"
        role           = "worker"
        count          = 1
        image          = "talos"
        cpu            = 4
        memory         = 8
        root_disk_size = 50
        ipv4           = "10.5.0.20"
      }
    ]
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 0
    error_message = "No controlplane machineconfig for a worker instance"
  }

  assert {
    condition     = length(data.talos_machine_configuration.worker) == 1
    error_message = "One worker machineconfig data source should be generated"
  }

  assert {
    condition     = length(keys(vsphere_virtual_machine.instances["worker"].extra_config)) == 2
    error_message = "Worker VM should receive guestinfo extra_config"
  }
}

# count > 1 expansion: 3 workers produce VMs named worker-1/worker-2/worker-3.
# Confirms the -N suffix and that one machineconfig data source is generated
# per expanded instance.
run "count_expansion" {
  command = plan

  variables {
    images = {
      talos = {
        url = "https://factory.talos.dev/image/903b2da78f99adef03cbbd4df6714563823f63218508800751560d3bc3557e40/v1.10.3/vmware-amd64.ova"
      }
    }
    instances = [
      {
        name   = "worker"
        role   = "worker"
        count  = 3
        image  = "talos"
        cpu    = 4
        memory = 8
        ipv4   = "10.5.0.20"
      }
    ]
  }

  assert {
    condition     = length(vsphere_virtual_machine.instances) == 3
    error_message = "count=3 should produce 3 VMs"
  }

  assert {
    condition     = contains(keys(vsphere_virtual_machine.instances), "worker-1") && contains(keys(vsphere_virtual_machine.instances), "worker-2") && contains(keys(vsphere_virtual_machine.instances), "worker-3")
    error_message = "Pool VMs should be named worker-1, worker-2, worker-3"
  }

  assert {
    condition     = length(data.talos_machine_configuration.worker) == 3
    error_message = "One worker machineconfig data source per expanded instance"
  }
}

# Non-cluster VM (custom role): no machineconfig is generated and extra_config
# is empty. No OVF deploy when no image is specified. Models utility VMs (jump
# host, historian, etc.) that sit next to Talos nodes on the same cluster.
run "non_cluster_vm" {
  command = plan

  variables {
    instances = [
      {
        name   = "historian"
        role   = "historian"
        count  = 1
        cpu    = 2
        memory = 4
      }
    ]
  }

  assert {
    condition     = length(vsphere_virtual_machine.instances) == 1
    error_message = "Non-cluster VM should still be created"
  }

  assert {
    condition     = length(keys(vsphere_virtual_machine.instances["historian"].extra_config)) == 0
    error_message = "Non-cluster VM should have empty extra_config — no guestinfo machineconfig"
  }

  assert {
    condition     = length(vsphere_virtual_machine.instances["historian"].ovf_deploy) == 0
    error_message = "No OVF deploy when instance has no image"
  }

  assert {
    condition     = length(data.talos_machine_configuration.controlplane) == 0 && length(data.talos_machine_configuration.worker) == 0
    error_message = "No machineconfigs generated for non-cluster roles"
  }
}

# Blank disk: instance with empty image creates a VM without OVF deploy.
# Models bring-your-own-disk provisioning or pre-installed VMs.
run "blank_disk_no_image" {
  command = plan

  variables {
    instances = [
      {
        name           = "jumpbox"
        count          = 1
        cpu            = 2
        memory         = 4
        root_disk_size = 50
      }
    ]
  }

  assert {
    condition     = length(vsphere_virtual_machine.instances) == 1
    error_message = "VM should be created even without an image"
  }

  assert {
    condition     = length(vsphere_virtual_machine.instances["jumpbox"].ovf_deploy) == 0
    error_message = "No OVF deploy when instance.image is empty"
  }
}

# Named resource pool: when resource_pool is non-empty, the module resolves the
# named pool data source and uses its ID for the VM.
run "named_resource_pool" {
  command = plan

  variables {
    resource_pool = "talos-pool"
  }

  assert {
    condition     = length(data.vsphere_resource_pool.named) == 1
    error_message = "Named resource pool data source should be created when resource_pool is set"
  }
}

# Root resource pool: empty resource_pool suppresses the named pool data source
# and the VM uses the compute cluster's built-in root pool.
run "root_resource_pool" {
  command = plan

  assert {
    condition     = length(data.vsphere_resource_pool.named) == 0
    error_message = "Named pool data source should be suppressed when resource_pool is empty"
  }
}

# Explicit folder: operator-supplied folder path is passed through verbatim.
run "custom_folder" {
  command = plan

  variables {
    folder = "prod/talos"
    instances = [
      {
        name   = "cp"
        role   = "controlplane"
        count  = 1
        cpu    = 2
        memory = 4
      }
    ]
  }

  assert {
    condition     = vsphere_virtual_machine.instances["cp"].folder == "prod/talos"
    error_message = "Explicit folder should be used verbatim"
  }
}

# Default folder: empty folder falls back to "windsor-{context_id}" so VMs are
# grouped by deployment when no explicit path is given.
run "default_folder" {
  command = plan

  variables {
    instances = [
      {
        name   = "cp"
        role   = "controlplane"
        count  = 1
        cpu    = 2
        memory = 4
      }
    ]
  }

  assert {
    condition     = vsphere_virtual_machine.instances["cp"].folder == "windsor-test"
    error_message = "Empty folder should default to windsor-{context_id}"
  }
}

# cluster_endpoint missing https:// prefix triggers the variable validation rule.
run "validation_cluster_endpoint_no_https" {
  command = plan

  variables {
    cluster_endpoint = "10.5.0.10:6443"
  }

  expect_failures = [
    var.cluster_endpoint,
  ]
}

# Image URL missing an http(s):// scheme triggers the images variable validation.
run "validation_image_url_missing_scheme" {
  command = plan

  variables {
    images = {
      bad = {
        url = "factory.talos.dev/image/abc/v1.10.3/vmware-amd64.ova"
      }
    }
  }

  expect_failures = [
    var.images,
  ]
}

# Invalid desired_state value triggers the instances variable validation.
run "validation_invalid_desired_state" {
  command = plan

  variables {
    instances = [
      {
        name          = "node"
        count         = 1
        cpu           = 2
        memory        = 4
        desired_state = "deleted"
      }
    ]
  }

  expect_failures = [
    var.instances,
  ]
}
