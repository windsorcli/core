#-----------------------------------------------------------------------------------------------------------------------
# Providers
#-----------------------------------------------------------------------------------------------------------------------

# Define the required Terraform providers
terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # Build the installer image URL based on Talos version and platform
  # For local platform (Docker), use the direct installer image
  # For other platforms with vanilla installations, use the factory pattern
  # If installer_image is explicitly provided, use that instead
  installer_image = var.installer_image != "" ? var.installer_image : "ghcr.io/siderolabs/installer:v${var.talos_version}"

  # Conditionally create the machine configuration patch based on disk_selector and hostname
  machine_config_patch = yamlencode({
    machine = merge(
      # Include hostname if provided
      var.hostname != null && var.hostname != "" ? {
        network = {
          hostname = var.hostname
        }
      } : {},
      # Build install block only for non-local platforms (Docker doesn't use installers)
      var.platform != "local" ? {
        install = merge(
          # Base install configuration
          # {
          #   image = local.installer_image
          #   wipe  = var.wipe_disk
          # },
          # Add disk selector if provided
          var.disk_selector != null ? {
            diskSelector = var.disk_selector
          } : {},
          # Add extra kernel args if provided
          length(var.extra_kernel_args) > 0 ? {
            extraKernelArgs = var.extra_kernel_args
          } : {},
          # Add extensions if provided
          length(var.extensions) > 0 ? {
            extensions = var.extensions
          } : {}
        )
      } : {}
    )
  })

  # Combine all configuration patches into one list, filtering out empty strings
  config_patches = compact(concat(
    [local.machine_config_patch],
    var.config_patches
  ))
}

#-----------------------------------------------------------------------------------------------------------------------
# Machine Configuration
#-----------------------------------------------------------------------------------------------------------------------

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

resource "talos_machine_bootstrap" "this" {
  count = var.bootstrap ? 1 : 0

  depends_on = [talos_machine_configuration_apply.this]

  client_configuration = var.client_configuration
  node                 = var.node
  endpoint             = var.endpoint
}

# Health check to ensure node is ready before dependent resources proceed
resource "null_resource" "node_health_check" {
  depends_on = [talos_machine_configuration_apply.this]

  triggers = {
    node_ip       = var.node
    talos_version = var.talos_version
    config_hash   = sha256(data.talos_machine_configuration.this.machine_configuration)
  }

  provisioner "local-exec" {
    command = "windsor check node-health --nodes ${var.node} --version ${var.talos_version} --timeout 300s"
  }
}
