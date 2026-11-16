# The Incus Host module manages server-scoped Incus objects that every context on one Incus cluster shares.

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
# Storage Pool
# =============================================================================

# The member storage pools define the pool on each member with its member-specific source.
resource "incus_storage_pool" "member" {
  for_each = var.members

  remote = var.remote
  target = each.key
  name   = var.storage_pool_name
  driver = var.storage_pool_driver
  config = {
    source = each.value.storage_source
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The incus_storage_pool creates the pool on every member once each member defines it.
resource "incus_storage_pool" "main" {
  remote      = var.remote
  name        = var.storage_pool_name
  driver      = var.storage_pool_driver
  description = "Shared instance storage"

  depends_on = [incus_storage_pool.member]

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Network
# =============================================================================

# The member networks define the physical network on each member with its member-specific parent.
resource "incus_network" "member" {
  for_each = var.network_name == null ? {} : var.members

  remote = var.remote
  target = each.key
  name   = var.network_name
  type   = "physical"
  config = {
    parent = each.value.network_parent
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The incus_network creates the physical network on every member once each member defines it.
resource "incus_network" "main" {
  count = var.network_name == null ? 0 : 1

  remote      = var.remote
  name        = var.network_name
  type        = "physical"
  description = "Shared LAN network"

  depends_on = [incus_network.member]

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Daemon Storage
# =============================================================================

locals {
  daemon_volume_keys = {
    images  = "storage.images_volume"
    backups = "storage.backups_volume"
    logs    = "storage.logs_volume"
  }

  daemon_volumes = var.daemon_storage_pool == null ? {} : {
    for pair in setproduct(keys(var.members), keys(local.daemon_volume_keys)) :
    "${pair[0]}/${pair[1]}" => { member = pair[0], name = pair[1] }
  }
}

# The incus_storage_volume holds one member's image, backup, or log files.
resource "incus_storage_volume" "daemon" {
  for_each = local.daemon_volumes

  remote       = var.remote
  target       = each.value.member
  pool         = var.daemon_storage_pool
  name         = each.value.name
  type         = "custom"
  content_type = "filesystem"

  depends_on = [incus_storage_pool.main]
}

# The incus_server points each member's image, backup, and log storage at its daemon volumes.
resource "incus_server" "member" {
  for_each = var.daemon_storage_pool == null ? {} : var.members

  remote = var.remote
  target = each.key
  config = {
    for name, key in local.daemon_volume_keys : key => "${var.daemon_storage_pool}/${name}"
  }

  depends_on = [incus_storage_volume.daemon]
}

# =============================================================================
# Projects
# =============================================================================

# The incus_project is the namespace that one context's profiles, images, volumes, and instances live in.
resource "incus_project" "main" {
  for_each = var.projects

  remote      = var.remote
  name        = each.key
  description = each.value.description
  config      = each.value.config
}

# =============================================================================
# Certificates
# =============================================================================

# The incus_certificate trusts one client, restricted to its projects when it lists any.
resource "incus_certificate" "main" {
  for_each = var.certificates

  remote      = var.remote
  name        = each.key
  certificate = each.value.certificate
  description = each.value.description
  type        = each.value.type
  restricted  = length(each.value.projects) > 0
  projects    = length(each.value.projects) > 0 ? each.value.projects : null

  depends_on = [incus_project.main]
}
