# workstation/incus tests: minimal, full, conditional (disabled_services), webhook/loadbalancer derivation.
mock_provider "incus" {
  mock_resource "incus_network" {}
  mock_resource "incus_instance" {}
}

mock_provider "local" {
  mock_resource "local_file" {}
}

# Minimal: required variables only; defaults for network, domain_name. Asserts network name, webhook/loadbalancer derivation, sequential IPs (dns=2, git=3), instance names.
run "minimal_configuration" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
  }

  assert {
    condition     = incus_network.main[0].name == "windsor-test"
    error_message = "Network name should be windsor-{context} (windsor-test when context=test)"
  }

  assert {
    condition     = local.webhook_host == local.loadbalancer_start_ip
    error_message = "Incus uses loadbalancer_start_ip for webhook"
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
    condition     = incus_instance.dns[0].name == "dns-test"
    error_message = "DNS instance name should use domain_name (dns.test when domain_name defaults to context)"
  }
}

# Full: all optional variables set; asserts custom network, domain_name, compose_project, custom registries, sequential IPs.
run "full_configuration" {
  command = plan

  variables {
    project_root = "/home/user/repo"
    context      = "dev"
    domain_name  = "local.dev"
    network_name = "windsor-dev"
    network_cidr = "10.20.0.0/16"
    enable_dns   = true
    enable_git   = true
    registries = {
      "gcr.io"  = { remote = "https://gcr.io" }
      "ghcr.io" = { remote = "https://ghcr.io" }
    }
  }

  assert {
    condition     = incus_network.main[0].name == "windsor-dev"
    error_message = "Network name should match variable"
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
    condition     = local.gateway == "10.20.0.1"
    error_message = "Gateway should be host 1 in network_cidr"
  }

  assert {
    condition     = local.dns_ip == "10.20.0.2" && local.git_ip == "10.20.0.3"
    error_message = "Sequential IPs: dns=2, git=3"
  }

  assert {
    condition     = local.service_ips["gcr.io"] == "10.20.0.4" && local.service_ips["ghcr.io"] == "10.20.0.5"
    error_message = "Sequential IPs: first two registries at 4 and 5"
  }

  assert {
    condition     = length(incus_instance.registry) == 2
    error_message = "Exactly two registry instances for custom registries map"
  }

  assert {
    condition     = incus_instance.dns[0].name == "dns-local-dev" && incus_instance.git[0].name == "git-local-dev"
    error_message = "Instance names should be sanitized for Incus (dots to hyphens): dns-local-dev, git-local-dev"
  }

  assert {
    condition     = length(incus_instance.dns) == 1 && length(incus_instance.git) == 1
    error_message = "DNS and git instances should be created when enabled"
  }
}

# Conditional: disabling DNS and git omits those instances and output keys.
run "disabled_services" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    enable_dns   = false
    enable_git   = false
  }

  assert {
    condition     = length(incus_instance.dns) == 0
    error_message = "DNS instance should not be created when enable_dns is false"
  }

  assert {
    condition     = length(incus_instance.git) == 0
    error_message = "Git instance should not be created when enable_git is false"
  }

  assert {
    condition     = length(incus_instance.registry) == 6
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

# Webhook and loadbalancer derived from network_cidr.
run "webhook_and_loadbalancer_derived_from_network_cidr" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    network_cidr = "10.10.0.0/16"
  }

  assert {
    condition     = local.loadbalancer_start_ip == "10.10.1.1"
    error_message = "loadbalancer_start_ip should be first host of next /24 from network_cidr"
  }

  assert {
    condition     = local.webhook_host == "10.10.1.1"
    error_message = "Webhook host should be loadbalancer_start_ip"
  }

  assert {
    condition     = local.dns_forward_target == "10.10.1.1"
    error_message = "dns_forward_target should be loadbalancer_start_ip"
  }
}

# Colima: use existing network (incusbr0); do not create. Same IP layout (dns=2, git=3, etc.).
run "create_network_false_uses_existing_network" {
  command = plan

  variables {
    project_root   = "/tmp/windsor-test"
    context        = "test"
    create_network = false
    network_name   = "incusbr0"
    network_cidr   = "10.5.0.0/16"
  }

  assert {
    condition     = length(incus_network.main) == 0
    error_message = "Network should not be created when create_network is false"
  }

  assert {
    condition     = local.attached_network == "incusbr0"
    error_message = "attached_network should be var.network_name when create_network is false"
  }

  assert {
    condition     = local.dns_ip == "10.5.0.2" && local.git_ip == "10.5.0.3"
    error_message = "IP layout unchanged: dns=2, git=3"
  }
}

# Registry hostname normalization: when key matches remote URL host, strip last dot-segment (TLD); local-only key used as-is.
run "registry_hostname_normalization" {
  command = plan

  variables {
    project_root = "/tmp/windsor-test"
    context      = "test"
    registries = {
      "gcr.io"         = { remote = "https://gcr.io" }
      "registry.k8s.io" = { remote = "https://registry.k8s.io" }
      registry         = { hostport = 5001 }
    }
  }

  assert {
    condition     = local.registry_hostname["gcr.io"] == "gcr.test" && local.registry_hostname["registry.k8s.io"] == "registry.k8s.test" && local.registry_hostname["registry"] == "registry.test"
    error_message = "Remote-match keys get TLD stripped (gcr.test, registry.k8s.test); local-only key used as-is (registry.test)"
  }

  assert {
    condition     = incus_instance.registry["gcr.io"].name == "gcr-test" && incus_instance.registry["registry.k8s.io"].name == "registry-k8s-test" && incus_instance.registry["registry"].name == "registry-test"
    error_message = "Incus instance names are sanitized (dots to hyphens) from normalized hostname"
  }
}
