#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">=1.8"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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

locals {
  upgrade_image = length(var.extensions) > 0 ? "factory.talos.dev/installer/${talos_image_factory_schematic.this[0].id}:v${var.talos_version}" : ""
}

#-----------------------------------------------------------------------------------------------------------------------
# In-place Upgrade — Controlplanes first, then Workers
#-----------------------------------------------------------------------------------------------------------------------
# Controlplanes and workers are separate resource blocks so depends_on guarantees all
# controlplane upgrades complete before any worker upgrade begins.
# Within each group, parallelism=1 on the terraform step (set in the facet) serializes nodes.
#
# windsor upgrade node handles: send upgrade → wait for reboot → verify healthy.
# Triggers on upgrade_image (extensions list or talos version changed) and node (IP changed).

resource "null_resource" "upgrade_controlplane" {
  for_each = local.upgrade_image != "" ? { for n in var.controlplanes : n.node => n } : {}

  triggers = {
    upgrade_image = local.upgrade_image
    node          = each.value.node
  }

  provisioner "local-exec" {
    command = "windsor upgrade node --node ${each.value.node} --image ${local.upgrade_image} --timeout 15m"
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
    upgrade_image = local.upgrade_image
    node          = each.value.node
  }

  provisioner "local-exec" {
    command = "windsor upgrade node --node ${each.value.node} --image ${local.upgrade_image} --timeout 15m"
    environment = {
      TALOSCONFIG = local.talosconfig_path
      KUBECONFIG  = local.kubeconfig_path
    }
  }
}
