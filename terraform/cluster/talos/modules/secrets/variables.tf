variable "talos_version" {
  description = "Pinned Talos version (semver, no v-prefix). Must match the talos_version cluster/talos and cluster/talos/config consume."
  type        = string
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version should be in semver format like '1.12.6'."
  }
}
