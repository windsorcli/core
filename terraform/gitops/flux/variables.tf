variable "flux_namespace" {
  description = "The namespace in which Flux will be installed"
  type        = string
  default     = "system-gitops"
}

variable "flux_operator_version" {
  description = "The version of the flux-operator and flux-instance Helm charts to install"
  type        = string
  # renovate: datasource=github-releases depName=flux-operator package=controlplaneio-fluxcd/flux-operator
  default = "0.61.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_operator_version))
    error_message = "The version must be in the format 'X.Y.Z'"
  }
}

variable "flux_version" {
  description = "The Flux distribution version the operator installs (FluxInstance spec.distribution.version)"
  type        = string
  # renovate: datasource=github-releases depName=flux package=fluxcd/flux2
  default = "2.9.6"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_version))
    error_message = "The version must be in the format 'X.Y.Z'"
  }
}

variable "chart_repository" {
  description = "OCI repository the flux-operator and flux-instance Helm charts are read from (e.g. oci://registry.example.com/charts)."
  type        = string
  default     = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  nullable    = false

  validation {
    condition     = can(regex("^oci://.+", var.chart_repository))
    error_message = "chart_repository must start with 'oci://'."
  }
}

variable "operator_image_repository" {
  description = "Image repository for the flux-operator, without a tag (e.g. registry.example.com/controlplaneio-fluxcd/flux-operator). The chart supplies the tag."
  type        = string
  default     = "ghcr.io/controlplaneio-fluxcd/flux-operator"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9._-]+)+$", var.operator_image_repository))
    error_message = "operator_image_repository must be a registry host with an optional port and an image path, with no scheme, tag, or trailing slash."
  }
}

variable "distribution_registry" {
  description = "Registry the Flux controller images are pulled from (FluxInstance spec.distribution.registry), e.g. registry.example.com/fluxcd."
  type        = string
  default     = "ghcr.io/fluxcd"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9._-]+)*$", var.distribution_registry))
    error_message = "distribution_registry must be a registry host with an optional port and path, with no scheme or trailing slash."
  }
}

variable "distribution_artifact" {
  description = "OCI artifact the flux-operator reads the Flux distribution manifests from (FluxInstance spec.distribution.artifact)."
  type        = string
  default     = "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests:latest"
  nullable    = false

  validation {
    condition     = can(regex("^oci://.+", var.distribution_artifact))
    error_message = "distribution_artifact must start with 'oci://'."
  }
}

variable "ready_gate_image" {
  description = "Image for the Job that waits for the FluxInstance to report Ready. It must provide kubectl and sh."
  type        = string
  # renovate: datasource=docker depName=kubectl package=alpine/k8s
  default  = "alpine/k8s:1.37.1@sha256:712dc5385d1c1a3f83b747fa9e40f64d433a97f72ff42f9755ff7dd1f62846e4"
  nullable = false

  validation {
    condition     = length(trimspace(var.ready_gate_image)) > 0 && !can(regex("://", var.ready_gate_image))
    error_message = "ready_gate_image must be an image reference with no scheme."
  }
}

variable "ssh_private_key" {
  description = "The private key to use for SSH authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_public_key" {
  description = "The public key to use for SSH authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_known_hosts" {
  description = "The known hosts to use for SSH authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_auth_secret" {
  description = "The name of the secret to store the git authentication details"
  type        = string
  default     = "flux-system"
}

variable "git_username" {
  description = "The git user to use to authenticte with the git provider"
  type        = string
  default     = "git"
}

variable "git_password" {
  description = "The git password or PAT used to authenticte with the git provider"
  type        = string
  default     = ""
  sensitive   = true
}

variable "webhook_token" {
  description = "Token used by the Flux notification-controller Receiver. When null or empty, a random 48-char token is generated and persisted in state."
  type        = string
  sensitive   = true
  default     = null
}

variable "concurrency" {
  description = "Number of concurrent reconciliations per Flux controller"
  type        = number
  default     = 2
}

variable "leader_election" {
  description = "Enable leader election on Flux controllers. Disable on single-node clusters to eliminate lease-renewal traffic against etcd."
  type        = bool
  default     = true
}

variable "replicas" {
  description = "Replica count for kustomize-controller, helm-controller, and notification-controller. source-controller stays pinned to 1 regardless of this value. Values above 1 require leader_election."
  type        = number
  default     = 1
}

variable "image_automation" {
  description = "Enable the Flux image-automation-controller. Only needed for automated image tag updates committed back to Git."
  type        = bool
  default     = false
}

variable "image_reflection" {
  description = "Enable the Flux image-reflector-controller. Only needed alongside image-automation-controller to scan image registries."
  type        = bool
  default     = false
}

variable "mode" {
  description = "GitOps reconciliation mode. 'push' installs notification-controller and creates the webhook-token secret. 'pull' omits both."
  type        = string
  default     = "push"

  validation {
    condition     = contains(["pull", "push"], var.mode)
    error_message = "mode must be 'pull' or 'push'"
  }
}
