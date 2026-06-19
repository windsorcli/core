// Define the required Terraform version and providers
terraform {
  required_version = ">= 1.12.2"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Machine Secrets
#-----------------------------------------------------------------------------------------------------------------------
# Cluster identity (CA, etcd CA, k8s CA, bootstrap token, encryption secret).
# Generated locally when no upstream secrets are supplied — the default for
# incus/metal/docker/aws/azure paths. On the hyperv CIDATA path, cluster/talos/config
# generates and exports them ahead of compute; they flow back here via
# var.machine_secrets / var.client_configuration and the count-gated resource
# below stays at zero. local.machine_secrets / local.client_configuration pick
# whichever source is active.
#
# Teardown caveat: regenerating secrets produces a NEW CA. Container nodes
# keep Talos state in Docker volumes; if those volumes were not removed,
# nodes still hold the OLD CA and the TLS handshake fails. Fix: full
# teardown including compute so controlplane container and its volumes are
# removed, then windsor apply (fresh node + fresh secrets).
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
  }
  input = local.cluster_endpoint
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # machine_secrets / client_configuration come from EITHER the upstream
  # cluster/talos/config module (when var.machine_secrets is set) OR the
  # locally-generated talos_machine_secrets resource (default). Every
  # downstream reference uses these locals — never the resource attributes
  # directly.
  machine_secrets      = var.machine_secrets != null ? var.machine_secrets : talos_machine_secrets.this[0].machine_secrets
  client_configuration = var.client_configuration != null ? var.client_configuration : talos_machine_secrets.this[0].client_configuration

  talosconfig      = data.talos_client_configuration.this.talos_config
  talosconfig_path = "${var.context_path}/.talos/config"
  kubeconfig_path  = "${var.context_path}/.kube/config"


  cluster_endpoint = var.cluster_endpoint != "" ? var.cluster_endpoint : (length(var.controlplanes) > 0 ? "https://${split(":", var.controlplanes[0].endpoint)[0]}:6443" : "")

  # When upstream secrets are supplied the per-node machineconfig was already
  # delivered out-of-band (hyperv CIDATA). Re-applying here would regenerate
  # without the per-node network patch and wipe the static IP back to DHCP.
  skip_machine_config_apply = var.machine_secrets != null

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
  source                    = "./modules/machine"
  node                      = var.controlplanes[0].node
  client_configuration      = local.client_configuration
  machine_secrets           = local.machine_secrets
  disk_selector             = lookup(var.controlplanes[0], "disk_selector", null)
  wipe_disk                 = lookup(var.controlplanes[0], "wipe_disk", true)
  extra_kernel_args         = lookup(var.controlplanes[0], "extra_kernel_args", [])
  cluster_name              = var.cluster_name
  cluster_endpoint          = local.cluster_endpoint
  kubernetes_version        = var.kubernetes_version
  talos_version             = var.talos_version
  machine_type              = "controlplane"
  endpoint                  = var.controlplanes[0].endpoint
  bootstrap                 = true // Bootstrap the first control plane node
  talosconfig_path          = local.talosconfig_path
  kubeconfig_path           = local.kubeconfig_path
  enable_health_check       = true
  skip_machine_config_apply = local.skip_machine_config_apply
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

  source                    = "./modules/machine"
  node                      = var.controlplanes[count.index + 1].node
  client_configuration      = local.client_configuration
  machine_secrets           = local.machine_secrets
  disk_selector             = lookup(var.controlplanes[count.index + 1], "disk_selector", null)
  wipe_disk                 = lookup(var.controlplanes[count.index + 1], "wipe_disk", true)
  extra_kernel_args         = lookup(var.controlplanes[count.index + 1], "extra_kernel_args", [])
  cluster_name              = var.cluster_name
  cluster_endpoint          = local.cluster_endpoint
  kubernetes_version        = var.kubernetes_version
  talos_version             = var.talos_version
  machine_type              = "controlplane"
  endpoint                  = var.controlplanes[count.index + 1].endpoint
  bootstrap                 = false // Do not bootstrap other control plane nodes
  talosconfig_path          = local.talosconfig_path
  kubeconfig_path           = local.kubeconfig_path
  enable_health_check       = true
  skip_machine_config_apply = local.skip_machine_config_apply
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

  source                    = "./modules/machine"
  node                      = var.workers[count.index].node
  client_configuration      = local.client_configuration
  machine_secrets           = local.machine_secrets
  disk_selector             = lookup(var.workers[count.index], "disk_selector", null)
  wipe_disk                 = lookup(var.workers[count.index], "wipe_disk", true)
  extra_kernel_args         = lookup(var.workers[count.index], "extra_kernel_args", [])
  cluster_name              = var.cluster_name
  cluster_endpoint          = local.cluster_endpoint
  kubernetes_version        = var.kubernetes_version
  talos_version             = var.talos_version
  machine_type              = "worker"
  endpoint                  = var.workers[count.index].endpoint
  talosconfig_path          = local.talosconfig_path
  kubeconfig_path           = local.kubeconfig_path
  enable_health_check       = true
  skip_machine_config_apply = local.skip_machine_config_apply
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


