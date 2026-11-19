variable "account_id" {
  description = "Cloudflare account that owns the tunnel."
  type        = string

  validation {
    condition     = trimspace(var.account_id) != ""
    error_message = "account_id must not be empty."
  }
}

variable "public_domain" {
  description = "Domain the tunnel serves. Every hostname under it routes to the origin service."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.public_domain))
    error_message = "public_domain must be a lowercase DNS name with no wildcard, scheme, or trailing dot."
  }
}

variable "zone_name" {
  description = "Cloudflare zone that holds public_domain. Null uses public_domain, which suits a domain that is itself a zone."
  type        = string
  default     = null
}

variable "name" {
  description = "Name prefix for the tunnel."
  type        = string
  default     = "windsor"
}

variable "origin_service" {
  description = "URL the tunnel forwards requests to."
  type        = string

  validation {
    condition     = startswith(var.origin_service, "https://")
    error_message = "origin_service must be an https:// URL so the connection to the gateway stays encrypted."
  }
}

variable "origin_ca_pool" {
  description = "Path inside the connector to a PEM CA bundle that verifies the origin certificate. Null uses the system roots."
  type        = string
  default     = null
}

variable "secret_version" {
  description = "Version of the tunnel secret. Raising it replaces the secret and produces a new token."
  type        = number
  default     = 1

  validation {
    condition     = var.secret_version >= 1 && var.secret_version == floor(var.secret_version)
    error_message = "secret_version must be a whole number of at least 1."
  }
}
