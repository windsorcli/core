# The Proxmox Host module manages host-level Proxmox VE objects that outlive a context.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116"
    }
  }
}

# =============================================================================
# Image Datastore
# =============================================================================

# The proxmox_storage_directory is the directory storage that receives downloaded images.
resource "proxmox_storage_directory" "images" {
  id               = var.image_datastore_id
  path             = var.image_datastore_path
  content          = ["import"]
  create_base_path = true
  nodes            = var.nodes

  lifecycle {
    prevent_destroy = true
  }
}
