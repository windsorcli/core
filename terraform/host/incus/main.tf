# The Incus Host module manages the storage pool that every context on one Incus cluster shares.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "1.2.1"
    }
  }
}

# =============================================================================
# Cluster
# =============================================================================

# The incus_cluster data source lists the members that each define the pool.
data "incus_cluster" "main" {
  remote = var.remote
}

locals {
  members = data.incus_cluster.main.is_clustered ? data.incus_cluster.main.members : {}
  dataset = "${var.storage_pool_name}/incus"
}

# =============================================================================
# Storage Pool
# =============================================================================

# The member storage pools define the pool on each member with its dataset.
resource "incus_storage_pool" "member" {
  for_each = local.members

  remote = var.remote
  target = each.key
  name   = var.storage_pool_name
  driver = "zfs"
  config = {
    source = local.dataset
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The incus_storage_pool creates the pool on every member, or on the one server when it is not clustered.
resource "incus_storage_pool" "main" {
  remote      = var.remote
  name        = var.storage_pool_name
  driver      = "zfs"
  description = "Shared instance storage"
  config      = length(local.members) > 0 ? {} : { source = local.dataset }

  depends_on = [incus_storage_pool.member]

  lifecycle {
    prevent_destroy = true
  }
}
