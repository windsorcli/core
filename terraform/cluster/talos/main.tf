// Define the required Terraform version and providers
terraform {
  required_version = ">=1.8"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Machine Secrets
#-----------------------------------------------------------------------------------------------------------------------
# When cluster state is destroyed and recreated, this resource generates a NEW CA. Container nodes keep Talos state
# in Docker volumes; if those volumes were not removed, the node still has the OLD CA and TLS handshake fails,
# so talos_machine_configuration_apply never succeeds (hangs or retries). Fix: full teardown including compute
# so controlplane container and its volumes are removed, then windsor up (fresh node + fresh secrets).
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"

  lifecycle {
    precondition {
      condition     = local.cluster_endpoint != "" && can(regex("^https://", local.cluster_endpoint))
      error_message = "cluster_endpoint could not be derived: set cluster.endpoint or ensure compute is applied so controlplanes have endpoints."
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  talosconfig      = data.talos_client_configuration.this.talos_config
  talosconfig_path = "${var.context_path}/.talos/config"
  kubeconfig_path  = "${var.context_path}/.kube/config"


  cluster_endpoint = var.cluster_endpoint != "" ? var.cluster_endpoint : (length(var.controlplanes) > 0 ? "https://${split(":", var.controlplanes[0].endpoint)[0]}:6443" : "")

  # extraMounts from raw volume strings (path or host:dest; path = part after ":" if present).
  # yamlencode() produces quoted keys (Terraform/Go); common_config_patches from blueprint is unquoted YAML. Both valid.
  controlplane_extra_mounts       = [for v in var.controlplane_volumes : { source = length(split(":", v)) > 1 ? split(":", v)[1] : v, destination = length(split(":", v)) > 1 ? split(":", v)[1] : v, type = "bind", options = ["rbind", "rw"] }]
  worker_extra_mounts             = [for v in var.worker_volumes : { source = length(split(":", v)) > 1 ? split(":", v)[1] : v, destination = length(split(":", v)) > 1 ? split(":", v)[1] : v, type = "bind", options = ["rbind", "rw"] }]
  controlplane_extra_mounts_patch = length(var.controlplane_volumes) > 0 ? yamlencode({ machine = { kubelet = { extraMounts = local.controlplane_extra_mounts } } }) : ""
  worker_extra_mounts_patch       = length(var.worker_volumes) > 0 ? yamlencode({ machine = { kubelet = { extraMounts = local.worker_extra_mounts } } }) : ""

  # Per-node UserVolumeConfig docs: node.disks if set, else pool-level (controlplane_disks / worker_disks).
  # Three cases, all resolved at plan time — no post-boot discovery needed:
  #   device set   → raw block volume (volumeType: disk), pinned to dev_path
  #   selector set → filesystem volume (xfs), CEL expression provided by caller (e.g. metal per-node serial)
  #   size only    → filesystem volume (xfs), size-based CEL (safe for provisioned platforms like Incus
  #                  where we created exactly one disk of that size)
  controlplane_block_docs = [for cp in var.controlplanes : [for i, d in lookup(cp, "disks", var.controlplane_disks) :
    try(d.device, "") != "" ? yamlencode({
      apiVersion = "v1alpha1", kind = "UserVolumeConfig", name = try(d.name, "disk-${i}"),
      volumeType = "disk", provisioning = { diskSelector = { match = "disk.dev_path == '${d.device}'" } }
      }) : yamlencode({
      apiVersion   = "v1alpha1", kind = "UserVolumeConfig", name = try(d.name, "disk-${i}"),
      provisioning = { diskSelector = { match = try(d.selector, "") != "" ? d.selector : "!system_disk && disk.size == ${d.size}u * GB" } },
      filesystem   = { type = "xfs" }
    })
    if try(d.device, "") != "" || try(d.selector, "") != "" || try(d.size, null) != null
  ]]
  worker_block_docs = [for w in var.workers : [for i, d in lookup(w, "disks", var.worker_disks) :
    try(d.device, "") != "" ? yamlencode({
      apiVersion = "v1alpha1", kind = "UserVolumeConfig", name = try(d.name, "disk-${i}"),
      volumeType = "disk", provisioning = { diskSelector = { match = "disk.dev_path == '${d.device}'" } }
      }) : yamlencode({
      apiVersion   = "v1alpha1", kind = "UserVolumeConfig", name = try(d.name, "disk-${i}"),
      provisioning = { diskSelector = { match = try(d.selector, "") != "" ? d.selector : "!system_disk && disk.size == ${d.size}u * GB" } },
      filesystem   = { type = "xfs" }
    })
    if try(d.device, "") != "" || try(d.selector, "") != "" || try(d.size, null) != null
  ]]
}

#-----------------------------------------------------------------------------------------------------------------------
# Control Planes
#-----------------------------------------------------------------------------------------------------------------------

module "controlplane_bootstrap" {
  source               = "./modules/machine"
  hostname             = try(var.controlplanes[0].hostname, "")
  node                 = var.controlplanes[0].node
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.controlplanes[0], "disk_selector", null)
  wipe_disk            = lookup(var.controlplanes[0], "wipe_disk", true)
  extra_kernel_args    = lookup(var.controlplanes[0], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = local.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "controlplane"
  endpoint             = var.controlplanes[0].endpoint
  bootstrap            = true // Bootstrap the first control plane node
  talosconfig_path     = local.talosconfig_path
  kubeconfig_path      = local.kubeconfig_path
  enable_health_check  = true
  config_patches = [for p in compact(concat([
    var.common_config_patches,
    var.controlplane_config_patches,
    local.controlplane_extra_mounts_patch,
    lookup(var.controlplanes[0], "config_patches", []),
  ], local.controlplane_block_docs[0])) : p if p != "null"]
}

module "controlplanes" {
  count      = max(length(var.controlplanes) - 1, 0) // Don't create more control planes if there are none
  depends_on = [module.controlplane_bootstrap]

  source               = "./modules/machine"
  hostname             = try(var.controlplanes[count.index + 1].hostname, "")
  node                 = var.controlplanes[count.index + 1].node
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.controlplanes[count.index + 1], "disk_selector", null)
  wipe_disk            = lookup(var.controlplanes[count.index + 1], "wipe_disk", true)
  extra_kernel_args    = lookup(var.controlplanes[count.index + 1], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = local.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "controlplane"
  endpoint             = var.controlplanes[count.index + 1].endpoint
  bootstrap            = false // Do not bootstrap other control plane nodes
  talosconfig_path     = local.talosconfig_path
  kubeconfig_path      = local.kubeconfig_path
  enable_health_check  = true
  config_patches = [for p in compact(concat([
    var.common_config_patches,
    var.controlplane_config_patches,
    local.controlplane_extra_mounts_patch,
    lookup(var.controlplanes[count.index + 1], "config_patches", []),
  ], local.controlplane_block_docs[count.index + 1])) : p if p != "null"]
}

#-----------------------------------------------------------------------------------------------------------------------
# Workers
#-----------------------------------------------------------------------------------------------------------------------

module "workers" {
  count      = length(var.workers)
  depends_on = [module.controlplane_bootstrap] // Depends on the first control plane completing

  source               = "./modules/machine"
  hostname             = try(var.workers[count.index].hostname, "")
  node                 = var.workers[count.index].node
  client_configuration = try(talos_machine_secrets.this.client_configuration, "")
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.workers[count.index], "disk_selector", null)
  wipe_disk            = lookup(var.workers[count.index], "wipe_disk", true)
  extra_kernel_args    = lookup(var.workers[count.index], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = local.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "worker"
  endpoint             = var.workers[count.index].endpoint
  talosconfig_path     = local.talosconfig_path
  kubeconfig_path      = local.kubeconfig_path
  enable_health_check  = true
  config_patches = [for p in compact(concat([
    var.common_config_patches,
    var.worker_config_patches,
    local.worker_extra_mounts_patch,
    lookup(var.workers[count.index], "config_patches", []),
  ], local.worker_block_docs[count.index])) : p if p != "null"]
}

#-----------------------------------------------------------------------------------------------------------------------
# Config Files
#-----------------------------------------------------------------------------------------------------------------------

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = var.controlplanes.*.endpoint
}

// Write Talos config to a local file. Content is updated when controlplane endpoints change (e.g. docker-desktop host-reachable 127.0.0.1).
resource "local_sensitive_file" "talosconfig" {
  count = trim(var.context_path, " ") != "" ? 1 : 0 // Create file only if path is specified and not empty/whitespace

  content         = data.talos_client_configuration.this.talos_config
  filename        = local.talosconfig_path
  file_permission = "0600" // Set file permissions to read/write for owner only
}


