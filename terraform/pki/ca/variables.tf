variable "common_name" {
  description = "CA certificate common name (generated only, ignored when cert/key are supplied)"
  type        = string
  default     = "Private CA"
}

variable "validity_period_hours" {
  description = "Certificate validity period in hours (generated only, ignored when cert/key are supplied)"
  type        = number
  default     = 87600 # 10 years
}

variable "cert" {
  description = "PEM-encoded CA certificate. Supply alongside key to bring your own; leave both empty to generate one."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = (var.cert != "") == (var.key != "")
    error_message = "cert and key must be supplied together"
  }
}

variable "key" {
  description = "PEM-encoded CA private key. Supply alongside cert to bring your own; leave both empty to generate one."
  type        = string
  default     = ""
  sensitive   = true
}
