# compute/docker tests: minimal, full, complex edge (localhost endpoints, no cluster_nodes), negative (validation).
mock_provider "docker" {
  mock_resource "docker_network" {}
  mock_resource "docker_image" {}
  mock_resource "docker_volume" {}
  mock_resource "docker_container" {}
}

# Applies to every run below, so tests don't shell out to a real Docker daemon.
override_data {
  target = data.external.docker_host
  values = {
    result = {
      ncpu     = "4"
      memtotal = "17179869184"
    }
  }
}

# Minimal: required for cluster path — context, network_cidr, create_network, cluster_nodes (1 cp, 0 workers). Default runtime colima.
run "minimal_configuration" {
  command = plan

  variables {
    context        = "test"
    network_cidr   = "10.5.0.0/16"
    create_network = true
    cluster_nodes = {
      distribution = "talos"
      controlplanes = {
        count     = 1
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        cpu       = 2
        memory    = 2
        volumes   = []
        hostports = []
      }
      workers = {
        count     = 0
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        cpu       = 4
        memory    = 4
        volumes   = []
        hostports = []
      }
    }
  }

  assert {
    condition     = length(docker_network.main) == 1
    error_message = "Network should be created when create_network is true"
  }

  assert {
    condition     = docker_network.main[0].name == "windsor-test"
    error_message = "Network name should be windsor-{context}"
  }

  assert {
    condition     = length(docker_container.containers) == 1
    error_message = "One controlplane container when cluster_nodes has 1 cp, 0 workers"
  }

  assert {
    condition     = docker_container.containers["controlplane-1"].dns == null
    error_message = "dns should be unset when dns_servers is not provided (Docker's default embedded resolver)"
  }

  assert {
    condition     = docker_container.containers["controlplane-1"].cpus == "2.0"
    error_message = "Container cpus should match cluster_nodes.controlplanes.cpu"
  }

  assert {
    condition     = docker_container.containers["controlplane-1"].memory == 2048
    error_message = "Container memory (MB) should match cluster_nodes.controlplanes.memory (GB) * 1024"
  }

  assert {
    condition     = length(output.controlplanes) == 1 && length(output.workers) == 0
    error_message = "controlplanes output length 1, workers length 0"
  }

  assert {
    condition     = output.network_name == "windsor-test"
    error_message = "network_name output should match created network"
  }

  assert {
    condition     = output.host_cpu == 4 && output.host_memory == 16
    error_message = "host_cpu/host_memory should come from the docker info override"
  }
}

# Full: multiple controlplanes and workers, docker-desktop runtime (localhost endpoints), custom network_cidr, hostports, volumes.
run "full_configuration" {
  command = plan

  variables {
    context        = "dev"
    network_cidr   = "10.20.0.0/16"
    create_network = true
    runtime        = "docker-desktop"
    dns_servers    = ["10.20.0.2"]
    cluster_nodes = {
      distribution = "talos"
      controlplanes = {
        count     = 2
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        cpu       = 4
        memory    = 8
        volumes   = ["/host/var:/var/mnt/local"]
        hostports = ["8443:6443/tcp"]
      }
      workers = {
        count     = 1
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        cpu       = 4
        memory    = 8
        volumes   = ["/host/data:/var/mnt/local"]
        hostports = []
      }
    }
  }

  assert {
    condition     = length(docker_container.containers) == 3
    error_message = "Two controlplanes and one worker container"
  }

  assert {
    condition     = length(output.controlplanes) == 2 && length(output.workers) == 1
    error_message = "controlplanes length 2, workers length 1"
  }

  assert {
    condition     = one(docker_network.main[0].ipam_config).subnet == "10.20.0.0/16"
    error_message = "Network CIDR should match variable"
  }

  assert {
    condition     = output.network_name == "windsor-dev"
    error_message = "network_name is windsor-{context}"
  }

  assert {
    condition     = alltrue([for c in docker_container.containers : contains(c.dns, "10.20.0.2")])
    error_message = "All node containers should get dns_servers when set"
  }

  assert {
    condition     = alltrue([for name, c in docker_container.containers : c.cpus == "4.0" if startswith(name, "controlplane-") || startswith(name, "worker-")])
    error_message = "Controlplane and worker containers should both get cpus == 4"
  }

  assert {
    condition     = docker_container.containers["worker-1"].memory == 8192
    error_message = "Worker container memory (MB) should match cluster_nodes.workers.memory (GB) * 1024"
  }
}

# Regression: a bare (colon-less) volume entry — the schema's own default for
# cluster.workers.volumes — must map host and container path to the same value,
# not an empty container_path.
run "bare_path_volume_entry" {
  command = plan

  variables {
    context        = "test"
    network_cidr   = "10.5.0.0/16"
    create_network = true
    cluster_nodes = {
      distribution = "talos"
      controlplanes = {
        count     = 1
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        cpu       = 2
        memory    = 2
        volumes   = []
        hostports = []
      }
      workers = {
        count     = 1
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        cpu       = 4
        memory    = 4
        volumes   = ["/var/mnt/local"]
        hostports = []
      }
    }
  }

  assert {
    condition     = contains([for v in docker_container.containers["worker-1"].volumes : v.container_path], "/var/mnt/local")
    error_message = "Bare volume entry must set container_path, not an empty string"
  }

  assert {
    condition     = contains([for v in docker_container.containers["worker-1"].volumes : v.host_path], "/var/mnt/local")
    error_message = "Bare volume entry must set host_path to the same value as container_path"
  }
}

# Complex: cluster_nodes = null yields no cluster containers; only instances when provided.
run "no_cluster_nodes_no_containers" {
  command = plan

  variables {
    context        = "test"
    network_cidr   = "10.5.0.0/16"
    create_network = true
    cluster_nodes  = null
    instances      = []
  }

  assert {
    condition     = length(docker_container.containers) == 0
    error_message = "No containers when cluster_nodes is null and instances is empty"
  }

  assert {
    condition     = length(output.controlplanes) == 0 && length(output.workers) == 0
    error_message = "controlplanes and workers outputs empty"
  }
}

# Regression: hostports applied only to first controlplane when no workers, only to first worker when workers exist (avoids port already allocated).
run "hostports_first_node_only" {
  command = plan

  variables {
    context        = "regress"
    network_cidr   = "10.30.0.0/16"
    create_network = true
    cluster_nodes = {
      distribution = "talos"
      controlplanes = {
        count     = 2
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        hostports = ["8443:6443/tcp"]
      }
      workers = {
        count     = 0
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        hostports = []
      }
    }
  }

  assert {
    condition     = contains(output.container_ports["controlplane-1"], "8443:6443/tcp") && !contains(output.container_ports["controlplane-2"], "8443:6443/tcp")
    error_message = "controlplanes.hostports must apply only to first controlplane when no workers"
  }
}

run "hostports_first_worker_only" {
  command = plan

  variables {
    context        = "regress"
    network_cidr   = "10.30.0.0/16"
    create_network = true
    cluster_nodes = {
      distribution = "talos"
      controlplanes = {
        count     = 1
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        hostports = []
      }
      workers = {
        count     = 2
        image     = "ghcr.io/siderolabs/talos:v1.11.5"
        hostports = ["9443:6443/tcp"]
      }
    }
  }

  assert {
    condition     = contains(output.container_ports["worker-1"], "9443:6443/tcp") && !contains(output.container_ports["worker-2"], "9443:6443/tcp")
    error_message = "workers.hostports must apply only to first worker"
  }
}

# Regression: runtime "docker" accepted and normalized to linux (aligned with workstation/docker).
run "runtime_docker_accepted" {
  command = plan

  variables {
    context        = "test"
    network_cidr   = "10.5.0.0/16"
    create_network = true
    runtime        = "docker"
    cluster_nodes = {
      distribution  = "talos"
      controlplanes = { count = 1, image = "ghcr.io/siderolabs/talos:v1.11.5" }
      workers       = { count = 0, image = "ghcr.io/siderolabs/talos:v1.11.5" }
    }
  }

  assert {
    condition     = length(docker_container.containers) == 1
    error_message = "runtime=docker should plan one container (normalized to linux)"
  }
}

# Negative: invalid cluster_nodes.distribution rejected.
run "invalid_distribution" {
  command         = plan
  expect_failures = [var.cluster_nodes]

  variables {
    context        = "test"
    network_cidr   = "10.5.0.0/16"
    create_network = true
    cluster_nodes = {
      distribution  = "k3s"
      controlplanes = { count = 1, image = "ghcr.io/siderolabs/talos:v1.11.5" }
      workers       = { count = 0, image = "ghcr.io/siderolabs/talos:v1.11.5" }
    }
  }
}
