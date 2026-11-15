#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.2"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  talosconfig_path = "${var.context_path}/.talos/config"
  kubeconfig_path  = "${var.context_path}/.kube/config"
}

#-----------------------------------------------------------------------------------------------------------------------
# Image Factory Schematic
#-----------------------------------------------------------------------------------------------------------------------
# Resolves the installer image URL for the requested extensions via the Talos Image Factory.
# The same schematic ID is stable across re-plans: factory.talos.dev deduplicates by content.

resource "talos_image_factory_schematic" "this" {
  count = length(var.extensions) > 0 ? 1 : 0

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.extensions
      }
    }
  })
}

# Nodes with a board overlay, such as rpi_5, take one schematic per overlay that holds the overlay and the
# extensions, installed from the metal installer.
locals {
  overlays = { for o in [for n in concat(var.controlplanes, var.workers) : n.overlay if n.overlay != null] : o.name => o... }
}

resource "talos_image_factory_schematic" "overlay" {
  for_each = length(var.extensions) > 0 ? local.overlays : {}

  schematic = yamlencode({
    overlay = {
      name  = each.value[0].name
      image = each.value[0].image
    }
    customization = {
      systemExtensions = {
        officialExtensions = var.extensions
      }
    }
  })
}

locals {
  upgrade_image = length(var.extensions) > 0 ? "factory.talos.dev/installer/${talos_image_factory_schematic.this[0].id}:v${var.talos_version}" : ""

  node_upgrade_images = local.upgrade_image == "" ? {} : { for n in concat(var.controlplanes, var.workers) : n.node => (
    n.install_image != null ? n.install_image :
    n.overlay != null ? "factory.talos.dev/metal-installer/${talos_image_factory_schematic.overlay[n.overlay.name].id}:v${var.talos_version}" :
    local.upgrade_image
  ) }
}

#-----------------------------------------------------------------------------------------------------------------------
# In-place Upgrade — Controlplanes first, then Workers
#-----------------------------------------------------------------------------------------------------------------------
# Controlplanes and workers are separate resource blocks so depends_on guarantees all
# controlplane upgrades complete before any worker upgrade begins.
# Within each group, parallelism=1 on the terraform step (set in the facet) serializes nodes.
#
# windsor upgrade node handles: send upgrade → wait for reboot → verify healthy.
# Triggers on upgrade_image (extensions list, overlay, or talos version changed) and node (IP changed).

resource "null_resource" "upgrade_controlplane" {
  for_each = local.upgrade_image != "" ? { for n in var.controlplanes : n.node => n } : {}

  triggers = {
    upgrade_image = local.node_upgrade_images[each.key]
    node          = each.value.node
  }

  provisioner "local-exec" {
    command = "windsor upgrade node --node ${each.value.node} --image ${local.node_upgrade_images[each.key]} --timeout 15m${var.powercycle_reboot ? " --reboot-mode powercycle" : ""}"
    environment = {
      TALOSCONFIG = local.talosconfig_path
      KUBECONFIG  = local.kubeconfig_path
    }
  }
}

resource "null_resource" "upgrade_worker" {
  for_each   = local.upgrade_image != "" ? { for n in var.workers : n.node => n } : {}
  depends_on = [null_resource.upgrade_controlplane]

  triggers = {
    upgrade_image = local.node_upgrade_images[each.key]
    node          = each.value.node
  }

  provisioner "local-exec" {
    command = "windsor upgrade node --node ${each.value.node} --image ${local.node_upgrade_images[each.key]} --timeout 15m${var.powercycle_reboot ? " --reboot-mode powercycle" : ""}"
    environment = {
      TALOSCONFIG = local.talosconfig_path
      KUBECONFIG  = local.kubeconfig_path
    }
  }
}
