variable "common_name" {
  description = "CA certificate common name (subject of the self-signed certificate and the CSR)"
  type        = string
  default     = "Private CA"
}

variable "validity_period_hours" {
  description = "Self-signed certificate validity period in hours (ignored when cert is supplied)"
  type        = number
  default     = 87600 # 10 years
}

variable "cert" {
  description = "PEM-encoded CA certificate chain. Supply alone to use a signed copy of csr, with key to bring your own CA, or leave empty to self-sign."
  type        = string
  default     = ""
  sensitive   = true
}

variable "key" {
  description = "PEM-encoded CA private key. Supply with cert to bring your own CA, or leave empty to generate one."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.key == "" || var.cert != ""
    error_message = "key requires cert"
  }
}
