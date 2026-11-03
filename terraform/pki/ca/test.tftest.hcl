mock_provider "tls" {}

variables {
  # Self-signed certificate for the public key in the tls_private_key overrides.
  signed_cert = <<-EOT
    -----BEGIN CERTIFICATE-----
    MIIBaTCCAQ6gAwIBAgIUInyinXuCJbdFGHcWTNmu4vzpkoIwCgYIKoZIzj0EAwIw
    GjEYMBYGA1UEAwwPVGVzdCBDbHVzdGVyIENBMB4XDTI2MTEwMzAxMDU0MloXDTM2
    MTAzMTAxMDU0MlowGjEYMBYGA1UEAwwPVGVzdCBDbHVzdGVyIENBMFkwEwYHKoZI
    zj0CAQYIKoZIzj0DAQcDQgAEdjNpQn2CY1pGBS1yV5gQowRPld/y1xRtXpyLHV5t
    Q39WHOFxJstSHmusmW+QUUxAH9DYvq5+MMzdm4TrjYY9waMyMDAwHQYDVR0OBBYE
    FP7ieR0cFjw8pESUDzaqPmCUDYsZMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0E
    AwIDSQAwRgIhAIzz1/ijMPpXoYVb8kyBzGclLbwZq9jaw0Ypm0jWpOvkAiEA6Trh
    XsjIL/Gp48AaDLFCOQEDsR9WaTvU0MbPr1NYgVI=
    -----END CERTIFICATE-----
  EOT
  other_cert  = <<-EOT
    -----BEGIN CERTIFICATE-----
    MIIBWjCCAQCgAwIBAgIUWZhVlo9t/M2Ld7wTsbRw1lL8oNkwCgYIKoZIzj0EAwIw
    EzERMA8GA1UEAwwIT3RoZXIgQ0EwHhcNMjYxMTAzMDEwNTQyWhcNMzYxMDMxMDEw
    NTQyWjATMREwDwYDVQQDDAhPdGhlciBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEH
    A0IABB009b0eeYWx6WTTMG1QCL6HFEwhNJEcIo0SkYiuGDDB5mpXfzZJJE+/kLGY
    kUbVHVYg/D4BpmolGNMoOG/hEqCjMjAwMB0GA1UdDgQWBBQvZPwE3g43QZVV8+pZ
    5gPtv3vSSzAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0gAMEUCIAXunDK0
    gbuj25SPfSeP3afaiiHXd1tBsXKIpOr0aS4pAiEAg1f24c2H/pBO4Sb3oGQJ4U3y
    lV1Bfy9/AngMeC2L0jE=
    -----END CERTIFICATE-----
  EOT
}

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

  assert {
    condition     = tls_cert_request.ca.subject[0].common_name == "Private CA"
    error_message = "CSR common name should match the CA common name"
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

run "cert_only_keeps_generated_key" {
  command = apply

  override_resource {
    target = tls_private_key.ca
    values = {
      public_key_pem = <<-EOT
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEdjNpQn2CY1pGBS1yV5gQowRPld/y
        1xRtXpyLHV5tQ39WHOFxJstSHmusmW+QUUxAH9DYvq5+MMzdm4TrjYY9wQ==
        -----END PUBLIC KEY-----
      EOT
    }
  }

  variables {
    cert = var.signed_cert
  }

  assert {
    condition     = length(tls_private_key.ca) == 1
    error_message = "cert without key should keep the generated CA private key"
  }

  assert {
    condition     = length(tls_self_signed_cert.ca) == 0
    error_message = "cert without key should not self-sign a CA certificate"
  }

  assert {
    condition     = output.cert == var.signed_cert
    error_message = "cert without key should output the supplied cert"
  }

  assert {
    condition     = output.key == tls_private_key.ca[0].private_key_pem
    error_message = "cert without key should output the generated key"
  }

  assert {
    condition     = tls_cert_request.ca.private_key_pem == tls_private_key.ca[0].private_key_pem
    error_message = "CSR should still be built from the generated CA key"
  }
}

run "cert_only_rejects_mismatched_key" {
  command = plan

  override_resource {
    target          = tls_private_key.ca
    override_during = plan
    values = {
      public_key_pem = <<-EOT
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEdjNpQn2CY1pGBS1yV5gQowRPld/y
        1xRtXpyLHV5tQ39WHOFxJstSHmusmW+QUUxAH9DYvq5+MMzdm4TrjYY9wQ==
        -----END PUBLIC KEY-----
      EOT
    }
  }

  variables {
    cert = var.other_cert
  }

  expect_failures = [
    output.cert,
  ]
}

run "key_without_cert_rejected" {
  command = plan

  variables {
    cert = ""
    key  = "-----BEGIN EC PRIVATE KEY-----\nfake\n-----END EC PRIVATE KEY-----\n"
  }

  expect_failures = [
    var.key,
  ]
}

run "cert_only_accepts_chain" {
  command = plan

  override_resource {
    target          = tls_private_key.ca
    override_during = plan
    values = {
      public_key_pem = <<-EOT
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEdjNpQn2CY1pGBS1yV5gQowRPld/y
        1xRtXpyLHV5tQ39WHOFxJstSHmusmW+QUUxAH9DYvq5+MMzdm4TrjYY9wQ==
        -----END PUBLIC KEY-----
      EOT
    }
  }

  variables {
    cert = "${var.signed_cert}${var.other_cert}"
  }

  assert {
    condition     = output.cert == "${var.signed_cert}${var.other_cert}"
    error_message = "cert without key should accept a chain led by the signed CA certificate"
  }
}
