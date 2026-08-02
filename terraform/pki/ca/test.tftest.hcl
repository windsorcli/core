mock_provider "tls" {}

run "generated_default" {
  command = plan

  variables {
    # Only required variables, all others use defaults
  }

  assert {
    condition     = length(tls_private_key.ca) == 1
    error_message = "no cert/key supplied should generate a CA private key"
  }

  assert {
    condition     = length(tls_self_signed_cert.ca) == 1
    error_message = "no cert/key supplied should generate a CA certificate"
  }

  assert {
    condition     = tls_self_signed_cert.ca[0].is_ca_certificate == true
    error_message = "Certificate must be marked as a CA"
  }

  assert {
    condition     = tls_self_signed_cert.ca[0].subject[0].common_name == "Private CA"
    error_message = "Common name should default to 'Private CA'"
  }

  assert {
    condition     = tls_self_signed_cert.ca[0].validity_period_hours == 87600
    error_message = "Validity period should default to 10 years"
  }
}

run "generated_custom_common_name" {
  command = plan

  variables {
    common_name           = "Test Org Root"
    validity_period_hours = 43800
  }

  assert {
    condition     = tls_self_signed_cert.ca[0].subject[0].common_name == "Test Org Root"
    error_message = "Common name should reflect the supplied value"
  }

  assert {
    condition     = tls_self_signed_cert.ca[0].validity_period_hours == 43800
    error_message = "Validity period should reflect the supplied value"
  }
}

run "byo_passes_through" {
  command = plan

  variables {
    cert = "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n"
    key  = "-----BEGIN EC PRIVATE KEY-----\nfake\n-----END EC PRIVATE KEY-----\n"
  }

  assert {
    condition     = length(tls_private_key.ca) == 0
    error_message = "cert/key supplied should not generate a CA private key"
  }

  assert {
    condition     = length(tls_self_signed_cert.ca) == 0
    error_message = "cert/key supplied should not generate a CA certificate"
  }

  assert {
    condition     = output.cert == var.cert
    error_message = "byo should pass the supplied cert straight through"
  }

  assert {
    condition     = output.key == var.key
    error_message = "byo should pass the supplied key straight through"
  }
}

run "cert_without_key_rejected" {
  command = plan

  variables {
    cert = "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n"
    key  = ""
  }

  expect_failures = [
    var.cert,
  ]
}

run "key_without_cert_rejected" {
  command = plan

  variables {
    cert = ""
    key  = "-----BEGIN EC PRIVATE KEY-----\nfake\n-----END EC PRIVATE KEY-----\n"
  }

  expect_failures = [
    var.cert,
  ]
}
