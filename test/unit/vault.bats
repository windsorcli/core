#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Vault Component Tests
# bats file_tags=security:vault
#-----------------------------------------------------------------------------------------------------------------------

@test "Secrets: Check vault pods" {
  check_pods_running "system-secrets" "app.kubernetes.io/name=vault" 1
}

@test "Secrets: Check vault-agent-injector pods" {
  check_pods_running "system-secrets" "app.kubernetes.io/name=vault-agent-injector" 1
}

@test "Secrets: Check vault service" {
  check_service_exists "system-secrets" "vault"
}

@test "Secrets: Check vault-active service" {
  check_service_exists "system-secrets" "vault-active"
}

@test "Secrets: Check vault-agent-injector-svc service" {
  check_service_exists "system-secrets" "vault-agent-injector-svc"
}

@test "Secrets: Check vault-internal service" {
  check_service_exists "system-secrets" "vault-internal"
}

@test "Secrets: Check vault-standby service" {
  check_service_exists "system-secrets" "vault-standby"
}

@test "Secrets: Check vault-ui service" {
  check_service_exists "system-secrets" "vault-ui"
}

@test "Secrets: Check Vault UI is available" {
  VAULT_URL="https://vault.${PRIVATE_DOMAIN_NAME}:8443"
  retry_until_success "$VAULT_URL/ui/vault/auth\?with\=token"
}

@test "Secrets: Authenticate and perform operations in Vault using CLI" {
  VAULT_URL="https://vault.${PRIVATE_DOMAIN_NAME}:8443"
  ROOT_TOKEN=$(kubectl get secret vault-root-token -n security -o jsonpath="{.data.root-token}" | base64 --decode)

  export VAULT_ADDR="$VAULT_URL"
  export VAULT_TOKEN="$ROOT_TOKEN"
  export VAULT_SKIP_VERIFY="true"

  # Authenticate with Vault
  run vault status
  [ "$status" -eq 0 ]

  run vault auth list
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubernetes/"* ]]

  run vault secrets list
  [ "$status" -eq 0 ]
  [[ "$output" == *"kvv2/"* ]]
}
