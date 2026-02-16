# workstation/docker tests: minimal, full, conditional (disabled_services), complex edge (webhook/loadbalancer derivation), negative (validation).
mock_provider "docker" {
  mock_resource "docker_network" {}
  mock_resource "docker_image" {}
  mock_resource "docker_container" {}
}

# Minimal: required variables only; defaults for runtime, network, domain_name, compose_project. only required variables (project_root, context); defaults for runtime, network, domain_name, compose_project.
# Asserts network name, colima runtime (no port publish), webhook/loadbalancer derivation, sequential IPs (dns=2, git=3), container names.
run "minimal_configuration" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    runtime      = "colima"
  }

  assert {
    condition     = docker_network.main.name == "windsor-test"
    error_message = "Network name should be windsor-{context} (windsor-test when context=test)"
  }

  assert {
    condition     = local.publish_ports == false
    error_message = "Colima runtime should not publish ports"
  }

  assert {
    condition     = local.webhook_host == local.loadbalancer_start_ip
    error_message = "Colima runtime should use loadbalancer_start_ip for webhook"
  }

  assert {
    condition     = local.webhook_host == "10.5.1.1"
    error_message = "With default network_cidr 10.5.0.0/16, loadbalancer_start_ip is 10.5.1.1"
  }

  assert {
    condition     = local.domain_name == "test"
    error_message = "domain_name should default to context when not set"
  }

  assert {
    condition     = local.compose_project == "workstation-windsor-test"
    error_message = "compose_project is workstation-windsor-{context}"
  }

  assert {
    condition     = local.dns_ip == "10.5.0.2"
    error_message = "Sequential IPs: dns should be host 2 in network_cidr"
  }

  assert {
    condition     = local.git_ip == "10.5.0.3"
    error_message = "Sequential IPs: git should be host 3 in network_cidr"
  }

  assert {
    condition     = docker_container.dns[0].name == "dns.test"
    error_message = "DNS container name should use domain_name (dns.test when domain_name defaults to context)"
  }
}

# Full: all optional variables set; asserts custom network, domain_name, compose_project, custom registries, sequential IPs, runtime logic.
run "full_configuration" {
  command = plan

  variables {
    project_root = "/home/user/repo"
    context      = "dev"
    context_path = "/home/user/repo/contexts/dev"
    domain_name  = "local.dev"
    runtime      = "docker-desktop"
    network_name = "windsor-dev"
    network_cidr = "10.20.0.0/16"
    enable_dns   = true
    enable_git   = true
    registries = {
      gcr  = { remote = "https://gcr.io" }
      ghcr = { remote = "https://ghcr.io" }
    }
  }

  assert {
    condition     = docker_network.main.name == "windsor-dev"
    error_message = "Network name should match variable"
  }

  assert {
    condition     = one(docker_network.main.ipam_config).subnet == "10.20.0.0/16"
    error_message = "Network CIDR should match variable"
  }

  assert {
    condition     = local.context_path_resolved == "/home/user/repo/contexts/dev"
    error_message = "context_path should be used when provided"
  }

  assert {
    condition     = local.domain_name == "local.dev"
    error_message = "domain_name should override context when set"
  }

  assert {
    condition     = local.compose_project == "workstation-windsor-dev"
    error_message = "compose_project is workstation-windsor-{context}"
  }

  assert {
    condition     = local.publish_ports == true
    error_message = "docker-desktop runtime should publish ports"
  }

  assert {
    condition     = local.gateway == "10.20.0.1"
    error_message = "Gateway should be host 1 in network_cidr"
  }

  assert {
    condition     = local.dns_ip == "10.20.0.2" && local.git_ip == "10.20.0.3"
    error_message = "Sequential IPs: dns=2, git=3"
  }

  assert {
    condition     = local.service_ips["gcr"] == "10.20.0.4" && local.service_ips["ghcr"] == "10.20.0.5"
    error_message = "Sequential IPs: first two registries at 4 and 5"
  }

  assert {
    condition     = length(docker_container.registry) == 2
    error_message = "Exactly two registry containers for custom registries map"
  }

  assert {
    condition     = docker_container.dns[0].name == "dns.local.dev" && docker_container.git[0].name == "git.local.dev"
    error_message = "Container names should use domain_name when set (dns.local.dev, git.local.dev)"
  }

  assert {
    condition     = local.webhook_host == "10.20.1.10"
    error_message = "docker-desktop webhook host should be host 10 in loadbalancer /24"
  }

  assert {
    condition     = local.dns_forward_target == "10.20.0.1:8053"
    error_message = "docker-desktop dns_forward_target should be gateway:8053"
  }

  assert {
    condition     = length(docker_container.dns) == 1 && length(docker_container.git) == 1
    error_message = "DNS and git containers should be created when enabled"
  }
}

# Conditional: disabling DNS and git omits those containers and output keys.
# DNS and git are disabled; only registry-related containers and dns/git are absent from output.
run "disabled_services" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    enable_dns   = false
    enable_git   = false
  }

  assert {
    condition     = length(docker_container.dns) == 0
    error_message = "DNS container should not be created when enable_dns is false"
  }

  assert {
    condition     = length(docker_container.git) == 0
    error_message = "Git container should not be created when enable_git is false"
  }

  assert {
    condition     = length(docker_container.registry) == 6
    error_message = "Default 6 registries should be created"
  }

  assert {
    condition     = !contains(keys(output.containers), "dns")
    error_message = "containers output should not include dns when disabled"
  }

  assert {
    condition     = !contains(keys(output.containers), "git")
    error_message = "containers output should not include git when disabled"
  }
}

# Complex: webhook_host and loadbalancer_start_ip derived from network_cidr (colima).
run "webhook_and_loadbalancer_derived_from_network_cidr" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    network_cidr = "10.10.0.0/16"
    runtime      = "colima"
  }

  assert {
    condition     = local.loadbalancer_start_ip == "10.10.1.1"
    error_message = "loadbalancer_start_ip should be first host of next /24 from network_cidr"
  }

  assert {
    condition     = local.webhook_host == "10.10.1.1"
    error_message = "Colima webhook host should be loadbalancer_start_ip"
  }

  assert {
    condition     = local.dns_forward_target == "10.10.1.1"
    error_message = "Colima dns_forward_target should be loadbalancer_start_ip"
  }
}

# Complex: docker-desktop webhook host is .10 in loadbalancer /24; dns_forward_target is gateway:8053.
run "webhook_host_docker_desktop_derived" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    network_cidr = "10.20.0.0/16"
    runtime      = "docker-desktop"
  }

  assert {
    condition     = local.loadbalancer_start_ip == "10.20.1.1"
    error_message = "loadbalancer_start_ip should be first host of next /24 from network_cidr"
  }

  assert {
    condition     = local.webhook_host == "10.20.1.10"
    error_message = "Docker-desktop webhook host should be host 10 in /24 containing loadbalancer_start_ip"
  }

  assert {
    condition     = local.dns_forward_target == "10.20.0.1:8053"
    error_message = "Docker-desktop dns_forward_target should be gateway:8053"
  }
}

# Negative: invalid runtime rejected.
run "invalid_runtime" {
  command         = plan
  expect_failures = [var.runtime]

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    runtime      = "invalid"
  }
}
