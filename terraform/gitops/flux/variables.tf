variable "flux_namespace" {
  description = "The namespace in which Flux will be installed"
  type        = string
  default     = "system-gitops"
}

variable "flux_operator_version" {
  description = "The version of the flux-operator Helm chart to install"
  type        = string
  # artifact: type=chart name=flux-operator repo=oci://ghcr.io/controlplaneio-fluxcd/charts
  default = "0.64.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_operator_version))
    error_message = "The version must be in the format 'X.Y.Z'"
  }
}

variable "flux_instance_version" {
  description = "The version of the flux-instance Helm chart to install"
  type        = string
  # artifact: type=chart name=flux-instance repo=oci://ghcr.io/controlplaneio-fluxcd/charts
  default = "0.64.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_instance_version))
    error_message = "The version must be in the format 'X.Y.Z'"
  }
}

variable "flux_version" {
  description = "The Flux distribution version the operator installs (FluxInstance spec.distribution.version)"
  type        = string
  # renovate: datasource=github-releases depName=flux package=fluxcd/flux2
  default = "2.10.1"

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
  description = "Image repository for the flux-operator, without a tag (e.g. registry.example.com/controlplaneio-fluxcd/flux-operator)."
  type        = string
  default     = "ghcr.io/controlplaneio-fluxcd/flux-operator"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9._-]+)+$", var.operator_image_repository))
    error_message = "operator_image_repository must be a registry host with an optional port and an image path, with no scheme, tag, or trailing slash."
  }
}

variable "operator_image_tag" {
  description = "Tag of the flux-operator image, with its digest."
  type        = string
  # artifact: type=image name=ghcr.io/controlplaneio-fluxcd/flux-operator
  default  = "v0.64.0@sha256:7f60122c5f07c51972ba86635783c5bcc6d450dea5d6f8291362efb1d81463e8"
  nullable = false
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

variable "controller_image_tags" {
  description = "Tag of each Flux controller image, with its digest. The images are read from <distribution_registry>/<controller>. The tags MUST match flux_version."
  type        = map(string)
  default = {
    # artifact: type=image name=ghcr.io/fluxcd/source-controller
    "source-controller" = "v1.10.2@sha256:1405a9e460833df9aff920664243c0df271f42be05e0bf38db31d2b7e9ebbaab"
    # artifact: type=image name=ghcr.io/fluxcd/kustomize-controller
    "kustomize-controller" = "v1.10.2@sha256:e122808057ef0f6a3cb7fbd8e256b5a528d8a59f41d237f2d6664f54481c26d9"
    # artifact: type=image name=ghcr.io/fluxcd/helm-controller
    "helm-controller" = "v1.7.2@sha256:cc944eff709767f9a4d22de6b52dfa330f872962465868ed7787320b056b84f8"
    # artifact: type=image name=ghcr.io/fluxcd/notification-controller
    "notification-controller" = "v1.10.1@sha256:229b0685768aec0adf7f0d9536890c93bcffc06b17336e1c1fdd4372c4c27dca"
    # artifact: type=image name=ghcr.io/fluxcd/image-reflector-controller
    "image-reflector-controller" = "v1.3.1@sha256:2b9bc474a0f806353e2367fad5cb1e05962c8c8f697979201446aa612b4cc532"
    # artifact: type=image name=ghcr.io/fluxcd/image-automation-controller
    "image-automation-controller" = "v1.3.1@sha256:63408d2ee35a1203d744561d8944dffed3d2c29c9dc18d99f82e1f2551675853"
  }
  nullable = false
}

variable "distribution_artifact" {
  description = "OCI artifact the flux-operator reads the Flux distribution manifests from (FluxInstance spec.distribution.artifact). When empty, the operator uses the manifests in its own image, which MUST include flux_version."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.distribution_artifact == "" || can(regex("^oci://.+", var.distribution_artifact))
    error_message = "distribution_artifact must be empty or start with 'oci://'."
  }
}

variable "distribution_variant" {
  description = "Flux distribution variant the controller images belong to (FluxInstance spec.distribution.variant). It MUST be set when distribution_registry is a mirror. When empty, the FluxInstance omits it."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "upstream-alpine", "enterprise-alpine", "enterprise-distroless", "enterprise-distroless-fips"], var.distribution_variant)
    error_message = "distribution_variant must be empty, upstream-alpine, enterprise-alpine, enterprise-distroless, or enterprise-distroless-fips."
  }
}

variable "image_pull_secret" {
  description = "Docker config JSON with credentials for the registries that serve the flux-operator and Flux controller images. When empty, the images are pulled anonymously."
  type        = string
  default     = ""
  nullable    = false
  sensitive   = true

  validation {
    condition     = var.image_pull_secret == "" || can(jsondecode(var.image_pull_secret).auths)
    error_message = "image_pull_secret must be empty or a Docker config JSON document with an auths key."
  }
}

variable "ready_gate_image" {
  description = "Image for the Job that waits for the FluxInstance to report Ready. It must provide kubectl and sh."
  type        = string
  # artifact: type=image name=ghcr.io/windsorcli/utils
  default  = "ghcr.io/windsorcli/utils:1.37.2-r2@sha256:b110d3232d20896f6ba314553dad5b29665a5facbaa5b211aee5e2774c6b7b18"
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
