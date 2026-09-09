#---------------------------------------------------------------------------------------------------
# Providers Configuration
#---------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

#---------------------------------------------------------------------------------------------------
# Locals
#---------------------------------------------------------------------------------------------------

locals {
  cluster_name    = var.cluster_name != "" ? var.cluster_name : "${var.name}-${var.context_id}"
  kubeconfig_path = "${var.context_path}/.kube/config"
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
  # Scopes the ephemeral bootstrap pool below to var.node_locations instead
  # of GKE's own regional-cluster default of every zone in the region.
  node_locations = var.node_locations

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
  name           = "system"
  cluster        = google_container_cluster.this.id
  location       = var.region
  node_locations = var.node_locations

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # total_*_node_count (not the per-zone min/max_node_count) so the system
  # pool's size stays a fixed total regardless of how many zones
  # node_locations spans, while every listed zone stays schedulable for
  # rebalancing. BALANCED spreads nodes across those zones instead of
  # packing them into whichever has capacity first.
  autoscaling {
    total_min_node_count = var.system_node_pool.autoscaling_enabled ? var.system_node_pool.min_count : var.system_node_pool.node_count
    total_max_node_count = var.system_node_pool.autoscaling_enabled ? var.system_node_pool.max_count : var.system_node_pool.node_count
    location_policy      = "BALANCED"
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

  # Machine type candidates per pool, in fallback order: an explicit
  # instance_types override if set, else the pool's class list.
  pools_machine_types = {
    for name, p in local.effective_pools : name => (
      try(length(p.instance_types), 0) > 0
      ? p.instance_types
      : lookup(var.class_machine_types, p.class, [""])
    )
  }

  # Fans each portable pool out into one GKE node pool per candidate
  # machine type, so cluster-autoscaler falls over to an alternate type
  # when the primary's zone/type combination hits ZONE_RESOURCE_POOL_EXHAUSTED.
  # Only the primary (index 0) is created for a fixed-count pool with
  # autoscaling off — there's no scale-up event to trigger a fallback, so
  # extra types would just be redundant standing capacity. An autoscaling
  # pool's fallbacks start at min 0 and share the primary's max, costing
  # nothing until the primary can't be scheduled.
  pools_resolved = merge([
    for name, p in local.effective_pools : {
      for idx, mtype in(
        local.pools_autoscaling[name].enabled
        ? local.pools_machine_types[name]
        : slice(local.pools_machine_types[name], 0, 1)
        ) : (idx == 0 ? name : "${name}-alt${idx}") => {
        machine_type        = mtype
        spot                = p.lifecycle == "spot"
        node_count          = idx == 0 ? p.count : null
        autoscaling_enabled = local.pools_autoscaling[name].enabled
        min_count           = local.pools_autoscaling[name].enabled ? (idx == 0 ? coalesce(local.pools_autoscaling[name].min, min(p.count, 1)) : 0) : null
        max_count           = local.pools_autoscaling[name].enabled ? coalesce(local.pools_autoscaling[name].max, max(p.count, 3)) : null
        disk_size_gb        = coalesce(p.root_disk_size, 100)
        labels = merge(p.labels, {
          "windsorcli.dev/pool"       = name
          "windsorcli.dev/pool-class" = p.class
        })
        taints = p.taints
      }
    }
  ]...)
}

resource "google_container_node_pool" "pools" {
  for_each       = local.pools_resolved
  name           = each.key
  cluster        = google_container_cluster.this.id
  location       = var.region
  node_locations = var.node_locations

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

#---------------------------------------------------------------------------------------------------
# Workload Identity for cert-manager
#
# GKE analogue of the AKS federated-identity-credential pair and the EKS
# create_cert_manager_role + Pod Identity association. cert-manager
# authenticates to Cloud DNS via GKE's own Workload Identity: the pod's
# ServiceAccount token is exchanged for a Google access token, scoped to a
# dedicated Google Service Account with roles/dns.admin on the specified
# zone(s). No key file stored anywhere.
#
# Off by default — only provisioned when ACME is in play (operator set
# dns.public_domain and the facet flips create_cert_manager_identity on).
#---------------------------------------------------------------------------------------------------

resource "google_service_account" "cert_manager" {
  count        = var.create_cert_manager_identity ? 1 : 0
  account_id   = "${local.cluster_name}-cert-manager"
  display_name = "cert-manager for ${local.cluster_name}"
  project      = var.project_id
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  count              = var.create_cert_manager_identity ? 1 : 0
  service_account_id = google_service_account.cert_manager[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[system-pki/cert-manager]"
}

resource "google_dns_managed_zone_iam_member" "cert_manager_dns" {
  for_each     = var.create_cert_manager_identity ? toset(var.cert_manager_dns_zone_names) : toset([])
  project      = var.project_id
  managed_zone = each.value
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.cert_manager[0].email}"
}

# cert-manager's cloudDNS solver has no way to target a zone by name — it
# calls ManagedZones.List to find the zone matching the challenge domain,
# an operation Cloud DNS IAM can't scope to a single zone resource. Granted
# project-wide, read-only; the write grant above stays zone-scoped.
resource "google_project_iam_member" "cert_manager_dns_list" {
  count   = var.create_cert_manager_identity ? 1 : 0
  project = var.project_id
  role    = "roles/dns.reader"
  member  = "serviceAccount:${google_service_account.cert_manager[0].email}"
}

#---------------------------------------------------------------------------------------------------
# Workload Identity for external-dns
#
# Same pattern as cert-manager. external-dns needs roles/dns.admin to
# create/update/delete record sets in the target zone. Default-on so any
# cluster on GKE can publish hostnames once the operator passes a zone
# name — matches the EKS/AKS facets' create_external_dns_role default.
#---------------------------------------------------------------------------------------------------

resource "google_service_account" "external_dns" {
  count        = var.create_external_dns_identity ? 1 : 0
  account_id   = "${local.cluster_name}-external-dns"
  display_name = "external-dns for ${local.cluster_name}"
  project      = var.project_id
}

resource "google_service_account_iam_member" "external_dns_workload_identity" {
  count              = var.create_external_dns_identity ? 1 : 0
  service_account_id = google_service_account.external_dns[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[system-dns/external-dns]"
}

resource "google_dns_managed_zone_iam_member" "external_dns_dns" {
  for_each     = var.create_external_dns_identity ? toset(var.external_dns_dns_zone_names) : toset([])
  project      = var.project_id
  managed_zone = each.value
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.external_dns[0].email}"
}

# external-dns's google provider always enumerates every zone in the
# project before filtering by domain, the same ManagedZones.List
# limitation as cert-manager above. Granted project-wide, read-only.
resource "google_project_iam_member" "external_dns_dns_list" {
  count   = var.create_external_dns_identity ? 1 : 0
  project = var.project_id
  role    = "roles/dns.reader"
  member  = "serviceAccount:${google_service_account.external_dns[0].email}"
}
