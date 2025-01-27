variable "flux_namespace" {
  description = "The namespace in which Flux will be installed"
  type        = string
  default     = "system-gitops"
}

variable "flux_helm_version" {
  description = "The version of Flux Helm chart to install"
  type        = string
  # renovate: datasource=helm depName=flux package=flux2 helmRepo=https://fluxcd-community.github.io/helm-charts
  default = "2.14.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_helm_version))
    error_message = "The version must be in the format 'X.Y.Z'"
  }
}

variable "flux_version" {
  description = "The version of Flux to install"
  type        = string
  # renovate: datasource=github-releases depName=flux package=fluxcd/flux2
  default = "2.4.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.flux_version))
    error_message = "The version must be in the format 'X.Y.Z'"
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
  description = "The token to use for the webhook"
  type        = string
  sensitive   = true
  default     = ""
}
