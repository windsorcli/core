# compute/docker tests: minimal, full, complex edge (localhost endpoints, no cluster_nodes), negative (validation).
mock_provider "docker" {
  mock_resource "docker_network" {}
  mock_resource "docker_image" {}
  mock_resource "docker_volume" {}
  mock_resource "docker_container" {}
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
    condition     = length(output.controlplanes) == 1 && length(output.workers) == 0
    error_message = "controlplanes output length 1, workers length 0"
  }

  assert {
    condition     = output.network_name == "windsor-test"
    error_message = "network_name output should match created network"
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
