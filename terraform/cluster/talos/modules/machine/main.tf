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
# Disks
#-----------------------------------------------------------------------------------------------------------------------

locals {

  # Conditionally create the machine configuration patch based on disk_selector and hostname
  machine_config_patch = yamlencode({
    machine = merge(
      # Include network block only if hostname is not null or empty
      var.hostname != null && var.hostname != "" ? {
        network = {
          hostname = var.hostname
        }
      } : {},
      # Include install block only if disk_selector is not null
      var.disk_selector != null ? {
        install = {
          diskSelector    = var.disk_selector     # Disk selector to use for the machine
          wipe            = var.wipe_disk         # Whether to wipe the disk before installation
          extraKernelArgs = var.extra_kernel_args # Additional kernel arguments
          image           = var.image             # Image to be used for installation
          extensions      = var.extensions        # Extensions to be used for installation
        }
      } : {}
    )
  })

  # Combine machine configuration patch with additional configuration patches
  config_patches = concat(
    [local.machine_config_patch],
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
