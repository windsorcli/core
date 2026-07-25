#---------------------------------------------------------------------------------------------------
# General Context
#---------------------------------------------------------------------------------------------------

variable "context_id" {
  description = "The windsor context id for this deployment; used to name and label resources."
  type        = string
  default     = ""
}

variable "context_path" {
  description = "The path to the context folder."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Additional labels for all resources."
  type        = map(string)
  default     = {}
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token for the hcloud and imager providers. Empty falls back to the HCLOUD_TOKEN environment variable."
  type        = string
  default     = ""
  sensitive   = true
}

#---------------------------------------------------------------------------------------------------
# Talos Image
#---------------------------------------------------------------------------------------------------

variable "talos_version" {
  description = "Talos version used to build the Image Factory snapshot (e.g. 1.13.7)."
  type        = string
  default     = "1.13.7"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "talos_version must be a bare semver like 1.13.7."
  }
}

variable "talos_schematic_id" {
  description = "Talos Image Factory schematic id for the hcloud image. Defaults to the empty (no-extension) schematic."
  type        = string
  default     = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
}

variable "image_ids" {
  description = "Pre-existing Hetzner snapshot ids by architecture (x86/arm). When set for an architecture, that snapshot is used instead of building one with the imager provider."
  type = object({
    x86 = optional(string, "")
    arm = optional(string, "")
  })
  default = {}
}

#---------------------------------------------------------------------------------------------------
# Placement
#---------------------------------------------------------------------------------------------------

variable "location" {
  description = "Hetzner datacenter location for servers (e.g. fsn1, nbg1, hel1, ash, hil, sin)."
  type        = string
  default     = "fsn1"
}

variable "network_zone" {
  description = "Hetzner network zone the private network spans (e.g. eu-central, us-east, us-west, ap-southeast)."
  type        = string
  default     = "eu-central"
}

variable "network_cidr" {
  description = "CIDR for the private network. A /24 node subnet is carved from it automatically."
  type        = string
  default     = "10.5.0.0/16"
  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid CIDR."
  }
}

variable "api_allowed_cidrs" {
  description = "Source CIDRs allowed to reach the Talos API (50000) and Kubernetes API (6443) on the public interface."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

#---------------------------------------------------------------------------------------------------
# Instances
#---------------------------------------------------------------------------------------------------

variable "instances" {
  description = "Node groups to provision. Each group expands into `count` servers named <name>-<n> (1-indexed). Architecture is derived from server_type (cax* → arm, otherwise x86)."
  type = list(object({
    name        = string
    role        = string
    count       = number
    server_type = string
  }))
  default = []
  validation {
    condition     = alltrue([for i in var.instances : contains(["controlplane", "worker"], i.role)])
    error_message = "Each instance group role must be either controlplane or worker."
  }
}
