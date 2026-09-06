#---------------------------------------------------------------------------------------------------
# Providers Configuration
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "google" {}

#---------------------------------------------------------------------------------------------------
# Locals
#---------------------------------------------------------------------------------------------------

locals {
  cluster_name    = var.cluster_name != "" ? var.cluster_name : "${var.name}-${var.context_id}"
  kubeconfig_path = "${var.context_path}/.kube/config"
}

# Every zone available in var.region. Node pools span all of them instead of
# GKE's own default subset, so a stockout in one zone doesn't leave a pool
# stuck retrying a single unavailable zone.
data "google_compute_zones" "available" {
  region = var.region
  status = "UP"
}

#---------------------------------------------------------------------------------------------------
# GKE Cluster
# GKE Standard control plane with Dataplane V2, Google's managed Cilium
# integration — the same shape cluster/azure-aks uses (network_data_plane =
# "cilium"), so Windsor's own cni/cilium kustomize component never installs
# here. Nodes are private (no public IP); the control plane keeps a public
# endpoint restricted to var.authorized_networks, matching how cluster/aws-eks
# and cluster/azure-aks expose their API servers.
#---------------------------------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  # checkov:skip=CKV_GCP_65: Google Groups RBAC needs a pre-existing Workspace
  # security group; out of scope for a bootstrap infra module.
  # checkov:skip=CKV_GCP_66: Binary Authorization needs an image-signing
  # pipeline this blueprint doesn't provide yet.
  # checkov:skip=CKV_GCP_12: Dataplane V2 enforces network policy natively;
  # the legacy network_policy addon is for Calico on the legacy datapath.
  name     = local.cluster_name
  location = var.region

  deletion_protection = false

  network    = var.network_id
  subnetwork = var.subnetwork_id

  # Every real node pool is a separate google_container_node_pool below,
  # matching the aws-eks/azure-aks pattern of an inline system pool plus
  # var.pools. The cluster's own default pool is removed immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Google's own service agent needs write access to reach the API server
  # for the ephemeral default pool this cluster removes on create.
  node_config {
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}

  datapath_provider           = "ADVANCED_DATAPATH"
  enable_intranode_visibility = true

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value
        display_name = "authorized"
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  enable_shielded_nodes = true

  resource_labels = {
    windsor_context_id = var.context_id
  }
}

#---------------------------------------------------------------------------------------------------
# System Node Pool
# Runs only cluster operators — a CriticalAddonsOnly taint keeps user
# workloads off it, matching the inline system pool on aws-eks/azure-aks.
#---------------------------------------------------------------------------------------------------

resource "google_container_node_pool" "system" {
  name     = "system"
  cluster  = google_container_cluster.this.id
  location = var.region
  # A single zone: GKE creates one instance group per listed zone, so a
  # fixed-count pool spanning every zone would run N nodes, not N total.
  node_locations = [data.google_compute_zones.available.names[0]]

  node_count = var.system_node_pool.autoscaling_enabled ? null : var.system_node_pool.node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  dynamic "autoscaling" {
    for_each = var.system_node_pool.autoscaling_enabled ? [1] : []
    content {
      min_node_count = var.system_node_pool.min_count
      max_node_count = var.system_node_pool.max_count
    }
  }

  node_config {
    machine_type = var.system_node_pool.machine_type
    disk_size_gb = var.system_node_pool.disk_size_gb

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    taint {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    labels = {
      "windsorcli.dev/pool"       = "system"
      "windsorcli.dev/pool-class" = "system"
    }
  }
}

#---------------------------------------------------------------------------------------------------
# Portable User Pools (var.pools)
# Resolves each portable pool into GKE-specific fields, mirroring
# cluster/aws-eks and cluster/azure-aks's own pools_resolved locals.
#---------------------------------------------------------------------------------------------------

locals {
  # Falls back to one autoscaling general pool when the operator declares
  # none, matching the aws-eks/azure-aks zero-config default.
  effective_pools = length(var.pools) > 0 ? var.pools : {
    general = {
      class          = "general"
      count          = 1
      lifecycle      = "on-demand"
      instance_types = null
      root_disk_size = null
      autoscaling    = null
      labels         = {}
      taints         = []
    }
  }

  pools_autoscaling = {
    for name, p in local.effective_pools : name => {
      enabled = try(p.autoscaling.enabled, null) != null ? p.autoscaling.enabled : p.class != "system"
      min     = p.autoscaling != null ? p.autoscaling.min : null
      max     = p.autoscaling != null ? p.autoscaling.max : null
    }
  }

  pools_resolved = {
    for name, p in local.effective_pools : name => {
      machine_type = (try(length(p.instance_types), 0) > 0
        ? p.instance_types[0]
      : lookup(var.class_machine_types, p.class, [""])[0])
      spot                = p.lifecycle == "spot"
      node_count          = p.count
      autoscaling_enabled = local.pools_autoscaling[name].enabled
      min_count           = local.pools_autoscaling[name].enabled ? coalesce(local.pools_autoscaling[name].min, min(p.count, 1)) : null
      max_count           = local.pools_autoscaling[name].enabled ? coalesce(local.pools_autoscaling[name].max, max(p.count, 3)) : null
      disk_size_gb        = coalesce(p.root_disk_size, 100)
      labels = merge(p.labels, {
        "windsorcli.dev/pool"       = name
        "windsorcli.dev/pool-class" = p.class
      })
      taints = p.taints
    }
  }
}

resource "google_container_node_pool" "pools" {
  for_each       = local.pools_resolved
  name           = each.key
  cluster        = google_container_cluster.this.id
  location       = var.region
  node_locations = data.google_compute_zones.available.names

  node_count = each.value.autoscaling_enabled ? null : each.value.node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  dynamic "autoscaling" {
    for_each = each.value.autoscaling_enabled ? [1] : []
    content {
      min_node_count = each.value.min_count
      max_node_count = each.value.max_count
    }
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    spot         = each.value.spot

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = each.value.labels

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }
}

#---------------------------------------------------------------------------------------------------
# Kubeconfig
# gcloud owns kubeconfig format; the module owns orchestration only, the
# same split cluster/azure-aks uses for `az aks get-credentials`.
#---------------------------------------------------------------------------------------------------

resource "null_resource" "kubeconfig" {
  count = var.context_path != "" ? 1 : 0

  triggers = {
    cluster_id = google_container_cluster.this.id
  }

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
    environment = {
      KUBECONFIG = local.kubeconfig_path
    }
  }
}
