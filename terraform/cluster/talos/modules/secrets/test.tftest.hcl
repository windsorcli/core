mock_provider "talos" {
  mock_resource "talos_machine_secrets" {}
}

# Single-purpose module: one resource, two outputs. Asserts shape only.
run "generates_secrets" {
  command = plan

  variables {
    talos_version = "1.12.6"
  }

  assert {
    condition     = talos_machine_secrets.this.talos_version == "v1.12.6"
    error_message = "talos_version input should be prefixed with 'v' for the resource"
  }
}

# Validation rejects non-semver values (e.g. 1.12 without patch).
run "rejects_invalid_version" {
  command = plan

  variables {
    talos_version = "1.12"
  }

  expect_failures = [var.talos_version]
}
