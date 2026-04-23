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

# Resource to apply the machine configuration to the node
resource "talos_machine_configuration_apply" "this" {
  client_configuration        = var.client_configuration                                    # Client configuration for authentication
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration # Machine configuration data
  node                        = var.node                                                    # Node identifier for the machine
  endpoint                    = var.endpoint                                                # Endpoint for the machine
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
  # Always use Talos API; during bootstrap also check Kubernetes API
  # Use the endpoint's host for health check so the host (where the provisioner runs) can reach the Talos API.
  # In docker-desktop, endpoint is 127.0.0.1:50000 while node is the container IP (10.5.0.10); the host must use 127.0.0.1.
  # Extract host by: removing optional protocol, taking host from host:port or path, then stripping port
  endpoint_ip          = can(regex("^https?://", var.endpoint)) ? split(":", split("/", split("://", var.endpoint)[1])[0])[0] : split(":", var.endpoint)[0]
  health_check_node    = local.endpoint_ip
  health_check_command = var.bootstrap ? "windsor check node-health --nodes ${local.health_check_node} --timeout 5m --k8s-endpoint --skip-services dashboard" : "windsor check node-health --nodes ${local.health_check_node} --timeout 5m --skip-services dashboard"

}

resource "null_resource" "node_healthcheck" {
  triggers = {
    node_id = var.node
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

