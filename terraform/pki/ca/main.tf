#-----------------------------------------------------------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.1"
    }
  }
}

#-----------------------------------------------------------------------------------------------------------------------
# Locals
#-----------------------------------------------------------------------------------------------------------------------

locals {
  cert_only = var.cert != "" && var.key == ""
  key_pem   = var.key != "" ? var.key : tls_private_key.ca[0].private_key_pem
  cert_pem  = var.cert != "" ? var.cert : tls_self_signed_cert.ca[0].cert_pem

  # DER bytes of the first supplied certificate and the generated public key, as Latin-1 strings.
  cert_b64       = try(regex("-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\\s]+)-----END", var.cert)[0], "")
  public_key_b64 = try(regex("-----BEGIN PUBLIC KEY-----([A-Za-z0-9+/=\\s]+)-----END", tls_private_key.ca[0].public_key_pem)[0], "")
  cert_der       = try(textdecodebase64(replace(local.cert_b64, "/\\s/", ""), "ISO-8859-1"), "")
  public_key_der = try(textdecodebase64(replace(local.public_key_b64, "/\\s/", ""), "ISO-8859-1"), "")
  cert_matches   = !local.cert_only || (local.public_key_der != "" && strcontains(local.cert_der, local.public_key_der))
}

#-----------------------------------------------------------------------------------------------------------------------
# Root CA
#-----------------------------------------------------------------------------------------------------------------------

resource "tls_private_key" "ca" {
  count       = var.key != "" ? 0 : 1
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  count           = var.cert != "" ? 0 : 1
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

#-----------------------------------------------------------------------------------------------------------------------
# Certificate Signing Request
#-----------------------------------------------------------------------------------------------------------------------

# The CSR is a signing request for the cluster CA key.
# It lets a site PKI team sign the cluster CA under its own root.
resource "tls_cert_request" "ca" {
  private_key_pem = local.key_pem

  subject {
    common_name = var.common_name
  }
}
