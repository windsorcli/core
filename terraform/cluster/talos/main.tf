// Define the required Terraform version and providers
terraform {
  required_version = ">=1.8"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.7.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Machine Secrets
#-----------------------------------------------------------------------------------------------------------------------

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  // Local variables for configuration paths and data
  talosconfig = data.talos_client_configuration.this.talos_config
  kubeconfig  = talos_cluster_kubeconfig.this.kubeconfig_raw

  talosconfig_path = "${var.context_path}/.talos/config"
  kubeconfig_path  = "${var.context_path}/.kube/config"
}

#-----------------------------------------------------------------------------------------------------------------------
# Control Planes
#-----------------------------------------------------------------------------------------------------------------------

module "controlplane_bootstrap" {
  source               = "./modules/machine"
  hostname             = var.controlplanes[0].hostname
  node                 = var.controlplanes[0].node
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.controlplanes[0], "disk_selector", null)
  wipe_disk            = lookup(var.controlplanes[0], "wipe_disk", true)
  extra_kernel_args    = lookup(var.controlplanes[0], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = var.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "controlplane"
  endpoint             = var.controlplanes[0].endpoint
  bootstrap            = true // Bootstrap the first control plane node
  config_patches = compact(concat([
    var.common_config_patches,
    var.controlplane_config_patches,
    lookup(var.controlplanes[0], "config_patches", []),
  ]))
}

module "controlplanes" {
  count      = max(length(var.controlplanes) - 1, 0) // Don't create more control planes if there are none
  depends_on = [module.controlplane_bootstrap]

  source               = "./modules/machine"
  hostname             = var.controlplanes[count.index + 1].hostname
  node                 = var.controlplanes[count.index + 1].node
  client_configuration = talos_machine_secrets.this.client_configuration
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.controlplanes[count.index + 1], "disk_selector", null)
  wipe_disk            = lookup(var.controlplanes[count.index + 1], "wipe_disk", true)
  extra_kernel_args    = lookup(var.controlplanes[count.index + 1], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = var.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "controlplane"
  endpoint             = var.controlplanes[count.index + 1].endpoint
  bootstrap            = false // Do not bootstrap other control plane nodes
  config_patches = compact(concat([
    var.common_config_patches,
    var.controlplane_config_patches,
    lookup(var.controlplanes[count.index + 1], "config_patches", []),
  ]))
}

#-----------------------------------------------------------------------------------------------------------------------
# Workers
#-----------------------------------------------------------------------------------------------------------------------

module "workers" {
  count      = length(var.workers)
  depends_on = [module.controlplane_bootstrap] // Depends on the first control plane completing

  source               = "./modules/machine"
  hostname             = var.workers[count.index].hostname
  node                 = var.workers[count.index].node
  client_configuration = try(talos_machine_secrets.this.client_configuration, "")
  machine_secrets      = try(talos_machine_secrets.this.machine_secrets, "")
  disk_selector        = lookup(var.workers[count.index], "disk_selector", null)
  wipe_disk            = lookup(var.workers[count.index], "wipe_disk", true)
  extra_kernel_args    = lookup(var.workers[count.index], "extra_kernel_args", [])
  cluster_name         = var.cluster_name
  cluster_endpoint     = var.cluster_endpoint
  kubernetes_version   = var.kubernetes_version
  talos_version        = var.talos_version
  machine_type         = "worker"
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

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [module.controlplane_bootstrap]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.controlplanes[0].node
  endpoint             = var.controlplanes[0].endpoint
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = var.controlplanes.*.endpoint
}

// Write kubeconfig to a local file
resource "local_sensitive_file" "kubeconfig" {
  count      = local.kubeconfig_path != "" ? 1 : 0 // Create file only if path is specified
  depends_on = [local_sensitive_file.talosconfig]  // Ensure Talos config is written first

  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = local.kubeconfig_path
  file_permission = "0600" // Set file permissions to read/write for owner only

  lifecycle {
    ignore_changes = [content] // Ignore changes to content to prevent unnecessary updates
  }
}

// Write Talos config to a local file
resource "local_sensitive_file" "talosconfig" {
  count = local.talosconfig_path != "" ? 1 : 0 // Create file only if path is specified

  content         = data.talos_client_configuration.this.talos_config
  filename        = local.talosconfig_path
  file_permission = "0600" // Set file permissions to read/write for owner only

  lifecycle {
    ignore_changes = [content] // Ignore changes to content to prevent unnecessary updates
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Cluster Health
#-----------------------------------------------------------------------------------------------------------------------

# The following workaround is required until resolution of https://github.com/siderolabs/terraform-provider-talos/issues/221

# data "talos_cluster_health" "this" {
#   depends_on = [
#     module.controlplane_bootstrap,
#     module.controlplanes,
#     module.workers
#   ]

#   client_configuration = talos_machine_secrets.this.client_configuration
#   control_plane_nodes  = var.controlplanes.*.node
#   worker_nodes         = var.workers.*.node
#   endpoints            = var.controlplanes.*.endpoint
# }

locals {
  healthcheck_command     = var.os_type == "unix" ? "${path.module}/resources/healthcheck.sh" : "${path.module}/resources/healthcheck.ps1"
  healthcheck_interpreter = var.os_type == "unix" ? ["sh", "-c"] : ["powershell", "-Command"]
}

resource "null_resource" "healthcheck" {
  triggers = {
    always_run = timestamp() // Ensures the resource runs every time
  }

  depends_on = [
    local_sensitive_file.kubeconfig,
    local_sensitive_file.talosconfig
  ]

  provisioner "local-exec" {
    command     = local.healthcheck_command
    interpreter = local.healthcheck_interpreter
    environment = {
      KUBECONFIG = local.kubeconfig_path
      NODE_COUNT = length(var.controlplanes) + length(var.workers)
      TIMEOUT    = 300 # 5 minutes
      INTERVAL   = 5   # 5 seconds
    }
  }
}
