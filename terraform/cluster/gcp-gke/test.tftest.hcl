mock_provider "google" {}

# Verifies default naming, Dataplane V2, workload identity, and the system
# node pool with no optional variables set.
run "minimal_configuration" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
  }

  assert {
    condition     = google_container_cluster.this.name == "cluster-test"
    error_message = "Cluster name should follow default naming convention"
  }

  assert {
    condition     = google_container_cluster.this.datapath_provider == "ADVANCED_DATAPATH"
    error_message = "Cluster should use Dataplane V2, Google's managed Cilium integration"
  }

  assert {
    condition     = google_container_cluster.this.workload_identity_config[0].workload_pool == "test-project.svc.id.goog"
    error_message = "Workload Identity pool should derive from project_id"
  }

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes == true
    error_message = "Nodes should be private by default"
  }

  assert {
    condition     = google_container_cluster.this.remove_default_node_pool == true
    error_message = "The cluster's own default node pool should be removed"
  }

  assert {
    condition     = google_container_node_pool.system.node_config[0].taint[0].key == "CriticalAddonsOnly"
    error_message = "System pool should carry the CriticalAddonsOnly taint"
  }

  assert {
    # A fixed total (min == max) via total_*_node_count, not node_count
    # directly — node_count on this resource is per zone, which would
    # multiply the pool's size under a multi-zone node_locations.
    condition     = google_container_node_pool.system.autoscaling[0].total_min_node_count == 1 && google_container_node_pool.system.autoscaling[0].total_max_node_count == 1
    error_message = "System pool should start with a fixed total of 1 node"
  }

  assert {
    condition     = google_container_node_pool.system.autoscaling[0].location_policy == "BALANCED"
    error_message = "System pool should spread across its eligible zones rather than pack into whichever has capacity first"
  }

  assert {
    condition     = length(google_container_node_pool.pools) == 1
    error_message = "No pools declared should fall back to one general pool"
  }

  assert {
    condition     = google_container_node_pool.pools["general"].node_config[0].machine_type == "n2-standard-4"
    error_message = "The fallback general pool should resolve to the default general machine type"
  }

  assert {
    condition     = toset(google_container_cluster.this.node_locations) == toset(["us-central1-a"])
    error_message = "The cluster's own bootstrap pool should stay in var.node_locations"
  }

  assert {
    condition     = toset(google_container_node_pool.system.node_locations) == toset(["us-central1-a"])
    error_message = "System pool should stay in var.node_locations"
  }

  assert {
    condition     = toset(google_container_node_pool.pools["general"].node_locations) == toset(["us-central1-a"])
    error_message = "Node pools should stay in var.node_locations"
  }
}

# system_node_pool's fields default independently, so a caller overriding
# just node_count (e.g. for topology: ha) doesn't have to restate the rest.
run "system_node_pool_partial_override_keeps_other_defaults" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    system_node_pool = {
      node_count = 2
    }
  }

  assert {
    condition     = google_container_node_pool.system.autoscaling[0].total_min_node_count == 2 && google_container_node_pool.system.autoscaling[0].total_max_node_count == 2
    error_message = "Overriding only node_count should take effect as the fixed total"
  }

  assert {
    condition     = google_container_node_pool.system.node_config[0].machine_type == "n2-standard-2"
    error_message = "Overriding only node_count should leave machine_type at its default"
  }

  assert {
    condition     = google_container_node_pool.system.node_config[0].disk_size_gb == 50
    error_message = "Overriding only node_count should leave disk_size_gb at its default"
  }
}

# topology: ha wires a multi-zone list; the cluster's bootstrap pool, the
# portable pools, and the system pool all stay eligible for every zone in it
# (a fixed-count portable pool's node_count multiplies per zone — the system
# pool doesn't, see below).
run "multi_zone_node_locations_spread_every_pool" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a", "us-central1-b", "us-central1-c"]
  }

  assert {
    condition     = toset(google_container_cluster.this.node_locations) == toset(["us-central1-a", "us-central1-b", "us-central1-c"])
    error_message = "The cluster's own bootstrap pool should span every zone in var.node_locations"
  }

  assert {
    condition     = toset(google_container_node_pool.pools["general"].node_locations) == toset(["us-central1-a", "us-central1-b", "us-central1-c"])
    error_message = "Node pools should span every zone in var.node_locations"
  }

  assert {
    condition     = toset(google_container_node_pool.system.node_locations) == toset(["us-central1-a", "us-central1-b", "us-central1-c"])
    error_message = "System pool should also stay eligible for every zone, not just a subset"
  }
}

# node_count on this resource is per zone, so a plain fixed node_count would
# multiply the system pool's size across a multi-zone node_locations.
# total_*_node_count keeps the total fixed regardless of zone count, while
# every zone in node_locations (asserted above) stays eligible for placement.
run "system_pool_total_stays_fixed_across_multiple_zones" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a", "us-central1-b", "us-central1-c"]
    system_node_pool = {
      node_count = 2
    }
  }

  assert {
    condition     = google_container_node_pool.system.autoscaling[0].total_min_node_count == 2 && google_container_node_pool.system.autoscaling[0].total_max_node_count == 2
    error_message = "System pool total should stay at 2 regardless of how many zones are eligible"
  }
}

# An empty node_locations list is rejected at validate time.
run "node_locations_empty_rejected" {
  command = plan
  expect_failures = [
    var.node_locations,
  ]
  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = []
  }
}

# Tests a full configuration with all optional variables explicitly set.
run "full_configuration" {
  command = plan

  variables {
    context_id             = "test"
    project_id             = "test-project"
    network_id             = "projects/test-project/global/networks/network-test"
    subnetwork_id          = "projects/test-project/regions/us-east1/subnetworks/private-test"
    node_locations         = ["us-east1-b"]
    cluster_name           = "custom-cluster"
    region                 = "us-east1"
    release_channel        = "STABLE"
    master_ipv4_cidr_block = "172.20.0.0/28"
    authorized_networks    = ["10.0.0.0/8"]
  }

  assert {
    condition     = google_container_cluster.this.name == "custom-cluster"
    error_message = "Cluster name should match input"
  }

  assert {
    condition     = google_container_cluster.this.location == "us-east1"
    error_message = "Cluster region should match input"
  }

  assert {
    condition     = google_container_cluster.this.release_channel[0].channel == "STABLE"
    error_message = "Release channel should match input"
  }

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].master_ipv4_cidr_block == "172.20.0.0/28"
    error_message = "Master CIDR block should match input"
  }

  assert {
    condition     = contains([for c in google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks : c.cidr_block], "10.0.0.0/8")
    error_message = "Authorized network should match input"
  }
}

# The kubeconfig resource is generated whenever context_path is set.
run "kubeconfig_generated_with_context_path" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    context_path   = "test"
  }

  assert {
    condition     = length(null_resource.kubeconfig) == 1
    error_message = "Kubeconfig resource should be created with a context path"
  }
}

run "no_kubeconfig_without_context_path" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    context_path   = ""
  }

  assert {
    condition     = try(length(null_resource.kubeconfig), 0) == 0
    error_message = "No kubeconfig resource should be created without a context path"
  }
}

# Empty pools falls back to a single autoscaling general pool.
run "pools_empty_falls_back_to_general_pool" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
  }

  assert {
    condition     = google_container_node_pool.pools["general"].autoscaling[0].min_node_count == 1
    error_message = "The fallback general pool should autoscale by default"
  }
}

# A declared pool's class resolves to the right default machine type family.
run "pools_resolves_class_to_machine_type" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    pools = {
      workers = {
        class = "compute"
        count = 2
      }
    }
  }

  assert {
    condition     = google_container_node_pool.pools["workers"].node_config[0].machine_type == "c2-standard-4"
    error_message = "A compute-class pool should resolve to the default compute machine type"
  }
}

# Explicit instance_types override the class default, and lifecycle: spot
# sets the node's spot flag.
run "pools_explicit_machine_type_and_spot_lifecycle" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    pools = {
      batch = {
        class          = "general"
        count          = 3
        lifecycle      = "spot"
        instance_types = ["n2-standard-16"]
      }
    }
  }

  assert {
    condition     = google_container_node_pool.pools["batch"].node_config[0].machine_type == "n2-standard-16"
    error_message = "Explicit instance_types should override the class default"
  }

  assert {
    condition     = google_container_node_pool.pools["batch"].node_config[0].spot == true
    error_message = "lifecycle: spot should set the node's spot flag"
  }
}

# A system-class pool with no explicit autoscaling stays fixed, matching the
# aws-eks/azure-aks class-default behavior.
run "pools_system_class_defaults_to_fixed" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    pools = {
      ops = {
        class = "system"
        count = 2
      }
    }
  }

  assert {
    condition     = length(google_container_node_pool.pools["ops"].autoscaling) == 0
    error_message = "A system-class pool should not autoscale unless explicitly enabled"
  }

  assert {
    condition     = google_container_node_pool.pools["ops"].node_count == 2
    error_message = "A fixed pool should set node_count directly"
  }
}

# Invalid pool class and pool name are both rejected at validate time.
run "pools_invalid_class_rejected" {
  command = plan
  expect_failures = [
    var.pools,
  ]
  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    pools = {
      bad = {
        class = "not-a-real-class"
        count = 1
      }
    }
  }
}

run "pools_invalid_name_rejected" {
  command = plan
  expect_failures = [
    var.pools,
  ]
  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
    pools = {
      "Not_Valid" = {
        class = "general"
        count = 1
      }
    }
  }
}

# cert-manager identity is off by default and external-dns is on, matching
# the AKS/EKS facets' defaults.
run "workload_identity_defaults" {
  command = plan

  variables {
    context_id     = "test"
    project_id     = "test-project"
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
  }

  assert {
    condition     = length(google_service_account.cert_manager) == 0
    error_message = "cert-manager identity should not be created by default."
  }

  assert {
    condition     = length(google_service_account.external_dns) == 1
    error_message = "external-dns identity should be created by default."
  }

  assert {
    condition     = google_service_account_iam_member.external_dns_workload_identity[0].member == "serviceAccount:test-project.svc.id.goog[system-dns/external-dns]"
    error_message = "external-dns Workload Identity binding should target the system-dns/external-dns KSA."
  }

  assert {
    condition     = google_project_iam_member.external_dns_dns_list[0].role == "roles/dns.reader"
    error_message = "external-dns should hold project-wide roles/dns.reader so it can list zones before filtering by domain."
  }
}

# Enabling cert-manager's identity scopes roles/dns.admin to exactly the
# zones passed in, one IAM member per zone.
run "cert_manager_identity_scoped_to_zones" {
  command = plan

  variables {
    context_id                   = "test"
    project_id                   = "test-project"
    network_id                   = "projects/test-project/global/networks/network-test"
    subnetwork_id                = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations               = ["us-central1-a"]
    create_cert_manager_identity = true
    cert_manager_dns_zone_names  = ["dns-test"]
  }

  assert {
    condition     = length(google_service_account.cert_manager) == 1
    error_message = "cert-manager identity should be created when requested."
  }

  assert {
    condition     = google_service_account_iam_member.cert_manager_workload_identity[0].member == "serviceAccount:test-project.svc.id.goog[system-pki/cert-manager]"
    error_message = "cert-manager Workload Identity binding should target the system-pki/cert-manager KSA."
  }

  assert {
    condition     = google_dns_managed_zone_iam_member.cert_manager_dns["dns-test"].role == "roles/dns.admin"
    error_message = "cert-manager should be granted roles/dns.admin on the requested zone."
  }

  assert {
    condition     = google_project_iam_member.cert_manager_dns_list[0].role == "roles/dns.reader"
    error_message = "cert-manager should hold project-wide roles/dns.reader — its cloudDNS solver calls ManagedZones.List and can't be scoped to one zone."
  }
}

# Verifies that a missing project_id is rejected.
run "missing_project_id" {
  command = plan
  expect_failures = [
    var.project_id,
  ]
  variables {
    context_id     = "test"
    project_id     = ""
    network_id     = "projects/test-project/global/networks/network-test"
    subnetwork_id  = "projects/test-project/regions/us-central1/subnetworks/private-test"
    node_locations = ["us-central1-a"]
  }
}
