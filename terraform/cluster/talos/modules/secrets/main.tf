# The Secrets submodule generates a Talos cluster's identity (CA, etcd CA,
# k8s CA, bootstrap token, encryption secret) once. cluster/talos calls it
# directly when no upstream secrets are supplied (default: incus/metal/docker
# /aws/azure paths). cluster/talos/config calls it via a sibling-tree path
# (../talos/modules/secrets) when preparing CIDATA seeds for hyperv — the
# secrets it produces are then exported back to cluster/talos via
# terraform_output so both stages sign + verify against the same cluster CA.
#
# The submodule is intentionally a thin wrapper over the talos_machine_secrets
# resource. Two callers means one location for secrets generation, but each
# top-level invocation produces its own state — sharing happens at the
# terraform_output layer, not via shared module state.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
    }
  }
}

# =============================================================================
# Cluster Identity
# =============================================================================

# The talos_machine_secrets resource generates a fresh Talos cluster identity:
# CA cert + key, bootstrap token, etcd CA, k8s CA, encryption secret.
# Destroying and recreating produces a different cluster — plan changes here
# are a signal that downstream nodes need to be re-imaged.
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}
