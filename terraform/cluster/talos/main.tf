// Define the required Terraform version and providers
terraform {
  required_version = ">= 1.12.2"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Machine Secrets
#-----------------------------------------------------------------------------------------------------------------------
# Cluster identity (CA, etcd CA, k8s CA, bootstrap token, encryption secret).
# Generated locally when no upstream secrets are supplied — the default for
# incus/metal/docker/aws/azure paths. On the hyperv CIDATA path, compute/hyperv
# generates and exports them; they flow back here via
# var.machine_secrets / var.client_configuration and the count-gated resource
# below stays at zero. local.machine_secrets / local.client_configuration pick
# whichever source is active.
#
# Full teardown (including compute) is required before re-apply: regenerating
# secrets mints a new CA, and leftover Docker volumes holding the old CA break
# the TLS handshake otherwise.
resource "talos_machine_secrets" "this" {
  count = var.machine_secrets == null ? 1 : 0

  talos_version = "v${var.talos_version}"

  lifecycle {
    # Workaround for siderolabs/terraform-provider-talos#352 — remove once fixed.
    ignore_changes = [talos_version]
  }
}

# State address migration: this resource used to be unconditional (no count
# gate) before var.machine_secrets / var.client_configuration were added.
# Introducing the count gate changes the address from `.this` to `.this[0]`;
# without a moved block, Terraform destroys and recreates, minting a fresh CA
# and breaking TLS with already-running nodes that still trust the old CA.
moved {
  from = talos_machine_secrets.this
  to   = talos_machine_secrets.this[0]
}

# Endpoint precondition. terraform_data is the standard "vehicle for preconditions"
# pattern used elsewhere in this repo (e.g. compute/incus). Hosted on a separate
# resource rather than the talos_machine_secrets lifecycle so it still fires when
# the secrets resource is count-gated off (hyperv path with upstream secrets).
resource "terraform_data" "endpoint_check" {
  lifecycle {
    precondition {
      condition     = local.cluster_endpoint != "" && can(regex("^https://", local.cluster_endpoint))
      error_message = "cluster_endpoint could not be derived: set cluster.endpoint or ensure compute is applied so controlplanes have endpoints."
    }
    precondition {
      condition     = var.vip_interface == null || local.vip != ""
      error_message = "vip_interface needs a cluster_endpoint host that is an IPv4 address no control plane uses."
    }
  }
  input = local.cluster_endpoint
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # machine_secrets / client_configuration come from EITHER an upstream
  # compute module (when var.machine_secrets is set) OR the locally-generated
  # talos_machine_secrets resource (default). Every downstream reference uses
  # these locals — never the resource attributes directly.
  machine_secrets      = var.machine_secrets != null ? var.machine_secrets : talos_machine_secrets.this[0].machine_secrets
  client_configuration = var.client_configuration != null ? var.client_configuration : talos_machine_secrets.this[0].client_configuration

  talosconfig      = data.talos_client_configuration.this.talos_config
  talosconfig_path = "${var.context_path}/.talos/config"
  kubeconfig_path  = "${var.context_path}/.kube/config"


  cluster_endpoint = var.cluster_endpoint != "" ? var.cluster_endpoint : (length(var.controlplanes) > 0 ? "https://${split(":", var.controlplanes[0].endpoint)[0]}:6443" : "")

  # Shared control-plane VIP: the cluster_endpoint host when vip_interface is set and no control plane uses it.
  cluster_endpoint_host = try(regex("^https://([^:/]+)", local.cluster_endpoint)[0], "")
  controlplane_hosts    = flatten([for cp in var.controlplanes : [cp.node, regex("^(?:[a-z]+://)?([^:/]+)", cp.endpoint)[0]]])
  vip                   = var.vip_interface != null && can(cidrhost("${local.cluster_endpoint_host}/32", 0)) && !contains(local.controlplane_hosts, local.cluster_endpoint_host) ? local.cluster_endpoint_host : ""
  vip_patch             = local.vip != "" ? yamlencode({ machine = { network = { interfaces = [merge(var.vip_interface, { vip = { ip = local.vip } })] } } }) : ""


  # Callers that deliver the machineconfig out of band (hyperv CIDATA) skip the
  # apply, which would otherwise wipe the per-node static IP back to DHCP.
  skip_machine_config_apply = var.skip_machine_config_apply != null ? var.skip_machine_config_apply : var.machine_secrets != null

  # extraMounts from raw volume strings (path or host:dest; path = part after ":" if present).
  # yamlencode() produces quoted keys (Terraform/Go); common_config_patches from blueprint is unquoted YAML. Both valid.
  controlplane_extra_mounts       = [for v in var.controlplane_volumes : { source = length(split(":", v)) > 1 ? split(":", v)[1] : v, destination = length(split(":", v)) > 1 ? split(":", v)[1] : v, type = "bind", options = ["rbind", "rw"] }]
  worker_extra_mounts             = [for v in var.worker_volumes : { source = length(split(":", v)) > 1 ? split(":", v)[1] : v, destination = length(split(":", v)) > 1 ? split(":", v)[1] : v, type = "bind", options = ["rbind", "rw"] }]
  controlplane_extra_mounts_patch = length(var.controlplane_volumes) > 0 ? yamlencode({ machine = { kubelet = { extraMounts = local.controlplane_extra_mounts } } }) : ""
  worker_extra_mounts_patch       = length(var.worker_volumes) > 0 ? yamlencode({ machine = { kubelet = { extraMounts = local.worker_extra_mounts } } }) : ""

  # Per-node UserVolumeConfig docs from node.disks; nodes without disks get none.
  # Three cases, all resolved at plan time — no post-boot discovery needed:
  #   device set   → raw block volume (volumeType: disk), pinned to dev_path
  #   selector set → filesystem volume (xfs), CEL expression provided by caller (e.g. metal per-node serial)
  #   size only    → filesystem volume (xfs), size-based CEL (safe for provisioned platforms like Incus
  #                  where we created exactly one disk of that size)
  controlplane_block_docs = [for cp in var.controlplanes : [for i, d in cp.disks :
    coalesce(d.device, "-") != "-" ? yamlencode({
      apiVersion = "v1alpha1", kind = "UserVolumeConfig", name = coalesce(d.name, "disk-${i}"),
      volumeType = "disk", provisioning = { diskSelector = { match = "disk.dev_path == '${d.device}'" } }
      }) : yamlencode({
      apiVersion   = "v1alpha1", kind = "UserVolumeConfig", name = coalesce(d.name, "disk-${i}"),
      provisioning = { diskSelector = { match = coalesce(d.selector, "-") != "-" ? d.selector : "!system_disk && disk.size == ${d.size}u * GB" } },
      filesystem   = { type = "xfs" }
    })
    if coalesce(d.device, "-") != "-" || coalesce(d.selector, "-") != "-" || d.size != null
  ]]
  worker_block_docs = [for w in var.workers : [for i, d in w.disks :
    coalesce(d.device, "-") != "-" ? yamlencode({
      apiVersion = "v1alpha1", kind = "UserVolumeConfig", name = coalesce(d.name, "disk-${i}"),
      volumeType = "disk", provisioning = { diskSelector = { match = "disk.dev_path == '${d.device}'" } }
      }) : yamlencode({
      apiVersion   = "v1alpha1", kind = "UserVolumeConfig", name = coalesce(d.name, "disk-${i}"),
      provisioning = { diskSelector = { match = coalesce(d.selector, "-") != "-" ? d.selector : "!system_disk && disk.size == ${d.size}u * GB" } },
      filesystem   = { type = "xfs" }
    })
    if coalesce(d.device, "-") != "-" || coalesce(d.selector, "-") != "-" || d.size != null
  ]]

  # Each node's config patches, in apply order: the common patches, the module's own patches, then the caller's role
  # and node patches, which win wherever they set the same key.
  controlplane_config_patches = [for i, cp in var.controlplanes : [for p in compact(concat(
    [var.common_config_patches, local.vip_patch, local.controlplane_extra_mounts_patch],
    local.controlplane_block_docs[i],
    [var.controlplane_config_patches, cp.config_patches],
  )) : p if p != "null"]]
  worker_config_patches = [for i, w in var.workers : [for p in compact(concat(
    [var.common_config_patches, local.worker_extra_mounts_patch],
    local.worker_block_docs[i],
    [var.worker_config_patches, w.config_patches],
  )) : p if p != "null"]]
}

#-----------------------------------------------------------------------------------------------------------------------
# Image Factory Overlays
#-----------------------------------------------------------------------------------------------------------------------
# One schematic per distinct board overlay, such as rpi_5 for a Raspberry Pi 5. A node with an overlay installs
# from that schematic's metal installer unless it sets install_image.

locals {
  overlays = { for o in [for n in concat(var.controlplanes, var.workers) : n.overlay if n.overlay != null] : o.name => o... }
}

resource "talos_image_factory_schematic" "overlay" {
  for_each = local.overlays

  schematic = yamlencode({
    overlay = {
      name  = each.value[0].name
      image = each.value[0].image
    }
  })
}

locals {
  controlplane_install_images = [for n in var.controlplanes :
    n.install_image != null ? n.install_image :
    n.overlay != null ? "factory.talos.dev/metal-installer/${talos_image_factory_schematic.overlay[n.overlay.name].id}:v${var.talos_version}" : null
  ]
  worker_install_images = [for n in var.workers :
    n.install_image != null ? n.install_image :
    n.overlay != null ? "factory.talos.dev/metal-installer/${talos_image_factory_schematic.overlay[n.overlay.name].id}:v${var.talos_version}" : null
  ]
}

#-----------------------------------------------------------------------------------------------------------------------
# Control Planes
#-----------------------------------------------------------------------------------------------------------------------

module "controlplane_bootstrap" {
  source                    = "./modules/machine"
  node                      = var.controlplanes[0].node
  client_configuration      = local.client_configuration
  machine_secrets           = local.machine_secrets
  disk_selector             = lookup(var.controlplanes[0], "disk_selector", null)
  wipe_disk                 = lookup(var.controlplanes[0], "wipe_disk", true)
  extra_kernel_args         = lookup(var.controlplanes[0], "extra_kernel_args", [])
  image                     = local.controlplane_install_images[0]
  cluster_name              = var.cluster_name
  cluster_endpoint          = local.cluster_endpoint
  kubernetes_version        = trimprefix(var.kubernetes_version, "v")
  talos_version             = var.talos_version
  machine_type              = "controlplane"
  endpoint                  = var.controlplanes[0].endpoint
  bootstrap                 = true // Bootstrap the first control plane node
  talosconfig_path          = local.talosconfig_path
  kubeconfig_path           = local.kubeconfig_path
  enable_health_check       = true
  skip_machine_config_apply = local.skip_machine_config_apply
  instance_id               = var.controlplanes[0].instance_id
  config_patches            = local.controlplane_config_patches[0]
}

module "controlplanes" {
  count = max(length(var.controlplanes) - 1, 0) // Don't create more control planes if there are none

  source                    = "./modules/machine"
  node                      = var.controlplanes[count.index + 1].node
  client_configuration      = local.client_configuration
  machine_secrets           = local.machine_secrets
  disk_selector             = lookup(var.controlplanes[count.index + 1], "disk_selector", null)
  wipe_disk                 = lookup(var.controlplanes[count.index + 1], "wipe_disk", true)
  extra_kernel_args         = lookup(var.controlplanes[count.index + 1], "extra_kernel_args", [])
  image                     = local.controlplane_install_images[count.index + 1]
  cluster_name              = var.cluster_name
  cluster_endpoint          = local.cluster_endpoint
  kubernetes_version        = trimprefix(var.kubernetes_version, "v")
  talos_version             = var.talos_version
  machine_type              = "controlplane"
  endpoint                  = var.controlplanes[count.index + 1].endpoint
  bootstrap                 = false // Do not bootstrap other control plane nodes
  talosconfig_path          = local.talosconfig_path
  kubeconfig_path           = local.kubeconfig_path
  enable_health_check       = true
  skip_machine_config_apply = local.skip_machine_config_apply
  instance_id               = var.controlplanes[count.index + 1].instance_id
  apply_after               = module.controlplane_bootstrap.health_check_id
  config_patches            = local.controlplane_config_patches[count.index + 1]
}

#-----------------------------------------------------------------------------------------------------------------------
# Workers
#-----------------------------------------------------------------------------------------------------------------------

module "workers" {
  count = length(var.workers)

  source                    = "./modules/machine"
  node                      = var.workers[count.index].node
  client_configuration      = local.client_configuration
  machine_secrets           = local.machine_secrets
  disk_selector             = lookup(var.workers[count.index], "disk_selector", null)
  wipe_disk                 = lookup(var.workers[count.index], "wipe_disk", true)
  extra_kernel_args         = lookup(var.workers[count.index], "extra_kernel_args", [])
  image                     = local.worker_install_images[count.index]
  cluster_name              = var.cluster_name
  cluster_endpoint          = local.cluster_endpoint
  kubernetes_version        = trimprefix(var.kubernetes_version, "v")
  talos_version             = var.talos_version
  machine_type              = "worker"
  endpoint                  = var.workers[count.index].endpoint
  talosconfig_path          = local.talosconfig_path
  kubeconfig_path           = local.kubeconfig_path
  enable_health_check       = true
  skip_machine_config_apply = local.skip_machine_config_apply
  instance_id               = var.workers[count.index].instance_id
  apply_after               = module.controlplane_bootstrap.health_check_id
  config_patches            = local.worker_config_patches[count.index]
}

#-----------------------------------------------------------------------------------------------------------------------
# In-place Talos Upgrade
#-----------------------------------------------------------------------------------------------------------------------
# Upgrades a node to its installer image (install_image, board overlay, else the stock installer) unless it already
# runs var.talos_version.
# Order: bootstrap control plane, other control planes, workers. The step MUST run with parallelism 1 so nodes in a group upgrade one at a time.

locals {
  stock_installer             = "ghcr.io/siderolabs/installer:v${var.talos_version}"
  controlplane_upgrade_images = [for image in local.controlplane_install_images : coalesce(image, local.stock_installer)]
  upgrade_flags               = "${var.powercycle_reboot ? " --reboot-mode powercycle" : ""}${var.upgrade_offline_timeout != "" ? " --offline-timeout ${var.upgrade_offline_timeout}" : ""}"
  worker_upgrade_images       = [for image in local.worker_install_images : coalesce(image, local.stock_installer)]
}

resource "terraform_data" "upgrade_bootstrap" {
  count      = var.upgrade_nodes && length(var.controlplanes) > 0 ? 1 : 0
  depends_on = [module.controlplane_bootstrap, module.controlplanes, module.workers]

  triggers_replace = [local.controlplane_upgrade_images[0]]

  provisioner "local-exec" {
    command = "windsor upgrade node --node ${var.controlplanes[0].node} --image ${local.controlplane_upgrade_images[0]} --skip-if-current --timeout ${var.upgrade_timeout}${local.upgrade_flags}"
    environment = {
      TALOSCONFIG = local.talosconfig_path
      KUBECONFIG  = local.kubeconfig_path
    }
  }
}

resource "terraform_data" "upgrade_controlplane" {
  count      = var.upgrade_nodes ? max(length(var.controlplanes) - 1, 0) : 0
  depends_on = [terraform_data.upgrade_bootstrap]

  triggers_replace = [local.controlplane_upgrade_images[count.index + 1]]

  provisioner "local-exec" {
    command = "windsor upgrade node --node ${var.controlplanes[count.index + 1].node} --image ${local.controlplane_upgrade_images[count.index + 1]} --skip-if-current --timeout ${var.upgrade_timeout}${local.upgrade_flags}"
    environment = {
      TALOSCONFIG = local.talosconfig_path
      KUBECONFIG  = local.kubeconfig_path
    }
  }
}

resource "terraform_data" "upgrade_worker" {
  count      = var.upgrade_nodes ? length(var.workers) : 0
  depends_on = [terraform_data.upgrade_bootstrap, terraform_data.upgrade_controlplane]

  triggers_replace = [local.worker_upgrade_images[count.index]]

  provisioner "local-exec" {
    command = "windsor upgrade node --node ${var.workers[count.index].node} --image ${local.worker_upgrade_images[count.index]} --skip-if-current --timeout ${var.upgrade_timeout}${local.upgrade_flags}"
    environment = {
      TALOSCONFIG = local.talosconfig_path
      KUBECONFIG  = local.kubeconfig_path
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Config Files
#-----------------------------------------------------------------------------------------------------------------------

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = local.client_configuration
  endpoints            = var.controlplanes.*.endpoint
}

// Write Talos config to a local file. Content is updated when controlplane endpoints change (e.g. docker-desktop host-reachable 127.0.0.1).
resource "local_sensitive_file" "talosconfig" {
  count = trim(var.context_path, " ") != "" ? 1 : 0 // Create file only if path is specified and not empty/whitespace

  content         = data.talos_client_configuration.this.talos_config
  filename        = local.talosconfig_path
  file_permission = "0600" // Set file permissions to read/write for owner only
}


