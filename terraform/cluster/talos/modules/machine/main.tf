#-----------------------------------------------------------------------------------------------------------------------
# Providers
#-----------------------------------------------------------------------------------------------------------------------

# Define the required Terraform providers
terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
    }
    null = {
      source = "hashicorp/null"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Disks
#-----------------------------------------------------------------------------------------------------------------------

locals {

  # Install block is patched only when a disk_selector is provided. Hostname is not patched:
  # Talos 1.12+ auto-derives machine.network.hostname from the runtime (Docker container name,
  # VM hostname, DHCP, etc.) and rejects an explicit override with "static hostname is already set".
  machine_config_patch = var.disk_selector != null ? yamlencode({
    machine = {
      install = {
        diskSelector    = var.disk_selector
        wipe            = var.wipe_disk
        extraKernelArgs = var.extra_kernel_args
        image           = var.image
      }
    }
  }) : ""

  config_patches = concat(
    compact([local.machine_config_patch]),
    [for patch in var.config_patches : patch]
  )
}

# Data source to generate the machine configuration for Talos
data "talos_machine_configuration" "this" {
  cluster_name       = var.cluster_name        # Name of the cluster
  machine_type       = var.machine_type        # Type of the machine (e.g., controlplane, worker)
  cluster_endpoint   = var.cluster_endpoint    # Endpoint for the cluster API
  machine_secrets    = var.machine_secrets     # Secrets for the machine
  kubernetes_version = var.kubernetes_version  # Kubernetes version to be installed
  talos_version      = "v${var.talos_version}" # Talos version to be used
  config_patches     = local.config_patches    # Configuration patches to apply
}

# Apply the machine configuration to the node. Skipped when the config is
# delivered out-of-band (CIDATA seed on hyperv) — re-applying would
# regenerate without the per-node network patch (lives in
# cluster/talos/config) and wipe the static IP back to DHCP.
resource "talos_machine_configuration_apply" "this" {
  count = var.skip_machine_config_apply ? 0 : 1

  client_configuration        = var.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = var.node
  endpoint                    = var.endpoint

  # Hardcoded: provider v0.11.0 types on_destroy attrs as Go bool, so var
  # references fail plan with "unknown value". Revisit when upstream fixes.
  on_destroy = {
    reset    = false
    graceful = true
    reboot   = false
  }
}

// Bootstrap the first control plane node
resource "talos_machine_bootstrap" "bootstrap" {
  count      = var.bootstrap ? 1 : 0
  depends_on = [talos_machine_configuration_apply.this]

  node                 = var.node
  endpoint             = var.endpoint
  client_configuration = var.client_configuration
}

#-----------------------------------------------------------------------------------------------------------------------
# Kubeconfig Generation
#-----------------------------------------------------------------------------------------------------------------------

resource "talos_cluster_kubeconfig" "this" {
  count      = var.bootstrap ? 1 : 0
  depends_on = [talos_machine_bootstrap.bootstrap]

  client_configuration = var.client_configuration
  node                 = var.node
  endpoint             = var.endpoint
}

// Write kubeconfig to a local file when bootstrap is true
resource "local_sensitive_file" "kubeconfig" {
  count = var.bootstrap && trim(var.kubeconfig_path, " ") != "" ? 1 : 0

  content         = talos_cluster_kubeconfig.this[0].kubeconfig_raw
  filename        = var.kubeconfig_path
  file_permission = "0600" // Set file permissions to read/write for owner only
}

#-----------------------------------------------------------------------------------------------------------------------
# Node Health Check
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # var.node is the Talos node identity apid routes to. The endpoint host
  # may be a forwarder address (loopback, bench NAT), not a valid identity.
  health_check_node    = var.node
  health_check_command = var.bootstrap ? "windsor check node-health --nodes ${local.health_check_node} --timeout 5m --k8s-endpoint --skip-services dashboard" : "windsor check node-health --nodes ${local.health_check_node} --timeout 5m --skip-services dashboard"
}

resource "null_resource" "node_healthcheck" {
  triggers = {
    node_id = var.node
    # Re-run when the applied machineconfig changes so a config update that
    # auto-reboots the node (talos_machine_configuration_apply mode=auto)
    # blocks downstream steps until the node is back healthy. Without this
    # trigger the resource is created once on first apply and never re-runs
    # for subsequent config diffs, leaving downstream terraform steps to
    # race against the reboot. When apply is skipped (out-of-band config
    # delivery) the trigger is constant — the config can't drift here.
    config_hash = try(talos_machine_configuration_apply.this[0].machine_configuration_hash, "skipped")

    # Re-run when the Talos version changes: it reboots the node, or replaces it
    # where the version is the node image (compute/docker). The triggers above
    # miss that (var.node keeps the reused IP, the machineconfig is unchanged),
    # so a replaced node only surfaced as a downstream failure against an
    # unreachable API.
    talos_version = var.talos_version
  }

  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.bootstrap,
    local_sensitive_file.kubeconfig
  ]

  provisioner "local-exec" {
    command = var.enable_health_check ? local.health_check_command : "echo 'Health check disabled'"
    environment = var.enable_health_check ? {
      TALOSCONFIG = var.talosconfig_path
      KUBECONFIG  = var.bootstrap ? var.kubeconfig_path : ""
    } : {}
  }
}

