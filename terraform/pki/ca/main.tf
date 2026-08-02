#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  byo = var.cert != "" && var.key != ""
}

#-----------------------------------------------------------------------------------------------------------------------
# Root CA
#-----------------------------------------------------------------------------------------------------------------------

resource "tls_private_key" "ca" {
  count       = local.byo ? 0 : 1
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  count           = local.byo ? 0 : 1
  private_key_pem = tls_private_key.ca[0].private_key_pem

  subject {
    common_name = var.common_name
  }

  validity_period_hours = var.validity_period_hours
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}
