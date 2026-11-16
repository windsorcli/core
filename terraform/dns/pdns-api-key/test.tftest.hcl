mock_provider "random" {}

run "generates_a_key" {
  command = plan

  assert {
    condition     = random_password.api_key.length == 48 && random_password.api_key.special == false
    error_message = "The API key should be 48 alphanumeric characters."
  }
}

run "rotation_is_a_keeper" {
  command = plan

  variables {
    rotation = "2"
  }

  assert {
    condition     = random_password.api_key.keepers.rotation == "2"
    error_message = "rotation should feed the key's keepers so changing it generates a new key."
  }
}
