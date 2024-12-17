// Define the required Terraform version and providers
terraform {
  required_version = ">=1.8"
  required_providers {
    talos = {
      source  = "siderolabs/talos"  // Talos provider source
      version = "0.6.1"            // Talos provider version
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"  // Kubernetes provider source
      version = "2.33.0"                // Kubernetes provider version
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Machine Secrets
#-----------------------------------------------------------------------------------------------------------------------

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"  // Specify the Talos version for machine secrets
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  // Local variables for configuration paths and data
  talosconfig = data.talos_client_configuration.this.talos_config
  kubeconfig  = local.modified_kubeconfig

  talosconfig_path = "${var.context_path}/.talos/config"  // Path to Talos config
  kubeconfig_path  = "${var.context_path}/.kube/config"   // Path to kubeconfig
}

#-----------------------------------------------------------------------------------------------------------------------
# Control Planes
#-----------------------------------------------------------------------------------------------------------------------

module "controlplanes" {
  // Use count to iterate over each control plane configuration
  count = length(var.controlplanes)

  source               = "./modules/machine"  // Source path for the machine module
  hostname             = var.controlplanes[count.index].hostname  // Hostname for the control plane
  node                 = var.controlplanes[count.index].node      // Node address for the control plane
  client_configuration = try(talos_machine_secrets.this.client_configuration, "")
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.controlplanes[count.index], "disk_selector", null)
  wipe_disk            = lookup(var.controlplanes[count.index], "wipe_disk", true)
  extra_kernel_args    = lookup(var.controlplanes[count.index], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = var.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "controlplane"  // Set machine type to control plane
  endpoint             = var.controlplanes[count.index].endpoint
  config_patches = compact(concat([
    var.common_config_patches,
    var.controlplane_config_patches,
    lookup(var.controlplanes[count.index], "config_patches", []),
  ]))
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [module.controlplanes]  // Ensure control planes are set up before bootstrapping

  node                 = var.controlplanes[0].node
  endpoint             = var.controlplanes[0].endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
}

#-----------------------------------------------------------------------------------------------------------------------
# Workers
#-----------------------------------------------------------------------------------------------------------------------

module "workers" {
  // Use count to iterate over each worker configuration
  count = length(var.workers)
  depends_on = [talos_machine_bootstrap.bootstrap]  // Ensure bootstrap is complete before setting up workers

  source               = "./modules/machine"  // Source path for the machine module
  hostname             = var.workers[count.index].hostname  // Hostname for the worker
  node                 = var.workers[count.index].node      // Node address for the worker
  client_configuration = try(talos_machine_secrets.this.client_configuration, "")
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.workers[count.index], "disk_selector", null)
  wipe_disk            = lookup(var.workers[count.index], "wipe_disk", true)
  extra_kernel_args    = lookup(var.workers[count.index], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = var.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "worker"  // Set machine type to worker
  endpoint             = var.workers[count.index].endpoint
  config_patches = compact(concat([
    var.common_config_patches,
    var.worker_config_patches,
    lookup(var.workers[count.index], "config_patches", []),
  ]))
}

#-----------------------------------------------------------------------------------------------------------------------
# Config Files
#-----------------------------------------------------------------------------------------------------------------------

data "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.bootstrap]  // Ensure bootstrap is complete before generating kubeconfig

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.controlplanes[0].node
  endpoint             = var.controlplanes[0].endpoint
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = var.controlplanes.*.endpoint
}

locals {
  // Generate and modify kubeconfig
  raw_kubeconfig = data.talos_cluster_kubeconfig.this.kubeconfig_raw

  modified_kubeconfig = replace(
    local.raw_kubeconfig,
    var.cluster_endpoint,
    var.cluster_endpoint
  )
}

resource "local_sensitive_file" "kubeconfig" {
  count      = local.kubeconfig_path != "" ? 1 : 0  // Create file only if path is specified
  depends_on = [local_sensitive_file.talosconfig]  // Ensure Talos config is written first

  content         = local.modified_kubeconfig
  filename        = local.kubeconfig_path
  file_permission = "0600"  // Set file permissions to read/write for owner only

  lifecycle {
    ignore_changes = [content]  // Ignore changes to content to prevent unnecessary updates
  }
}

resource "local_sensitive_file" "talosconfig" {
  count = local.talosconfig_path != "" ? 1 : 0  // Create file only if path is specified

  content         = data.talos_client_configuration.this.talos_config
  filename        = local.talosconfig_path
  file_permission = "0600"  // Set file permissions to read/write for owner only

  lifecycle {
    ignore_changes = [content]  // Ignore changes to content to prevent unnecessary updates
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Cluster Health
#-----------------------------------------------------------------------------------------------------------------------

data "talos_cluster_health" "this" {
  depends_on = [talos_machine_bootstrap.bootstrap]  // Ensure bootstrap is complete before checking cluster health

  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = var.controlplanes.*.node
  endpoints            = var.controlplanes.*.endpoint
  worker_nodes         = var.workers.*.node
}
