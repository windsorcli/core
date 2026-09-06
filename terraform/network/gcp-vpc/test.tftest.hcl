mock_provider "google" {}

# Verifies default naming, subnet CIDR derivation, and firewall/NAT wiring
# with no optional variables set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id = "test"
  }

  assert {
    condition     = google_compute_network.this.name == "network-test"
    error_message = "Network name should follow default naming convention"
  }

  assert {
    condition     = google_compute_network.this.auto_create_subnetworks == false
    error_message = "Network should not auto-create subnetworks"
  }

  assert {
    condition     = google_compute_subnetwork.public.ip_cidr_range == cidrsubnet("10.0.0.0/16", 4, 1)
    error_message = "Public subnet CIDR should derive from the default cidr_block"
  }

  assert {
    condition     = google_compute_subnetwork.private.ip_cidr_range == cidrsubnet("10.0.0.0/16", 2, 1)
    error_message = "Private subnet CIDR should derive from the default cidr_block"
  }

  assert {
    condition     = google_compute_subnetwork.isolated.ip_cidr_range == cidrsubnet("10.0.0.0/16", 4, 0)
    error_message = "Isolated subnet CIDR should derive from the default cidr_block"
  }

  assert {
    condition     = google_compute_subnetwork.public.private_ip_google_access == true
    error_message = "Public subnet should have private Google access enabled"
  }

  assert {
    condition     = google_compute_subnetwork.private.private_ip_google_access == true
    error_message = "Private subnet should have private Google access enabled"
  }

  assert {
    condition     = google_compute_subnetwork.isolated.private_ip_google_access == true
    error_message = "Isolated subnet should have private Google access enabled"
  }

  assert {
    condition     = length(google_compute_subnetwork.public.log_config) == 1
    error_message = "Public subnet should have VPC Flow Logs enabled by default"
  }

  assert {
    condition     = length(google_compute_subnetwork.private.log_config) == 1
    error_message = "Private subnet should have VPC Flow Logs enabled by default"
  }

  assert {
    condition     = length(google_compute_subnetwork.isolated.log_config) == 1
    error_message = "Isolated subnet should have VPC Flow Logs enabled by default"
  }

  assert {
    condition     = length(google_compute_router.this) == 1
    error_message = "Cloud Router should be created by default"
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 1
    error_message = "Cloud NAT should be created by default"
  }

  assert {
    condition     = length(google_compute_firewall.iap_ingress) == 1
    error_message = "IAP ingress firewall rule should be created by default"
  }
}

# Tests a full configuration with all optional variables explicitly set.
run "full_configuration" {
  command = plan

  variables {
    context_id           = "test"
    region               = "us-east1"
    network_name         = "custom-network"
    cidr_block           = "10.5.0.0/16"
    public_subnet_cidr   = "10.5.16.0/20"
    private_subnet_cidr  = "10.5.64.0/18"
    isolated_subnet_cidr = "10.5.0.0/20"
    enable_nat           = false
    enable_iap_ingress   = false
    enable_flow_logs     = false
  }

  assert {
    condition     = google_compute_network.this.name == "custom-network"
    error_message = "Network name should match input"
  }

  assert {
    condition     = google_compute_subnetwork.public.region == "us-east1"
    error_message = "Public subnet region should match input"
  }

  assert {
    condition     = google_compute_subnetwork.public.ip_cidr_range == "10.5.16.0/20"
    error_message = "Public subnet CIDR should match input"
  }

  assert {
    condition     = google_compute_subnetwork.private.ip_cidr_range == "10.5.64.0/18"
    error_message = "Private subnet CIDR should match input"
  }

  assert {
    condition     = google_compute_subnetwork.isolated.ip_cidr_range == "10.5.0.0/20"
    error_message = "Isolated subnet CIDR should match input"
  }

  assert {
    condition     = length(google_compute_router.this) == 0
    error_message = "Cloud Router should not be created when enable_nat is false"
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 0
    error_message = "Cloud NAT should not be created when enable_nat is false"
  }

  assert {
    condition     = length(google_compute_firewall.iap_ingress) == 0
    error_message = "IAP ingress firewall rule should not be created when disabled"
  }

  assert {
    condition     = length(google_compute_subnetwork.public.log_config) == 0
    error_message = "Public subnet should not have VPC Flow Logs when disabled"
  }
}

# The internal and health-check firewall rules are unconditional — a
# cluster can't come up without them, unlike NAT or IAP which are optional.
run "unconditional_firewall_rules_always_present" {
  command = plan

  variables {
    context_id = "test"
    enable_nat = false
  }

  assert {
    condition     = contains(google_compute_firewall.internal.source_ranges, "10.0.0.0/16")
    error_message = "Internal firewall rule should scope to the VPC's own CIDR"
  }

  assert {
    condition     = contains(google_compute_firewall.health_checks.source_ranges, "130.211.0.0/22")
    error_message = "Health check firewall rule should include the load balancer range"
  }
}

# Verifies that a missing context_id is rejected.
run "missing_context_id" {
  command = plan
  expect_failures = [
    var.context_id,
  ]
  variables {
    context_id = ""
  }
}
