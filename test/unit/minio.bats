#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"

  # Set MinIO URL
  MINIO_URL="https://minio.${PRIVATE_DOMAIN_NAME}:443"
}

#-----------------------------------------------------------------------------------------------------------------------
# MinIO Component Tests
# bats file_tags=storage:object,baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "Object Store: Check minio-operator pods" {
  run check_pods_running "system-object-store" "app.kubernetes.io/instance=minio-operator" 2
  [ "$status" -eq 0 ]
}

@test "Object Store: Check common-console service" {
  run check_service_exists "system-object-store" "common-console"
  [ "$status" -eq 0 ]
}

@test "Object Store: Check minio service" {
  run check_service_exists "system-object-store" "minio"
  [ "$status" -eq 0 ]
}

@test "Object Store: Check operator service" {
  run check_service_exists "system-object-store" "operator"
  [ "$status" -eq 0 ]
}

@test "Object Store: Check sts service" {
  run check_service_exists "system-object-store" "sts"
  [ "$status" -eq 0 ]
}

@test "Object Store: Check tenants.minio.min.io CRD version" {
  run check_crd_version "tenants.minio.min.io" "v2"
  [ "$status" -eq 0 ]
}

@test "Object Store: Validate MinIO Tenant with Credentials" {
  # Get and decode the secret
  run kubectl get secret minio-root-creds -n system-object-store -o jsonpath='{.data.config\.env}'
  [ "$status" -eq 0 ] || { echo "Failed to get secret: $output"; return 1; }
  
  CONFIG_ENV=$(echo "$output" | base64 --decode)
  eval $CONFIG_ENV

  run mc --insecure alias set mycloud "${MINIO_URL}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
  
  if [ "$status" -ne 0 ]; then
    echo "Failed to set MinIO alias. Debugging information:"
    echo "PRIVATE_DOMAIN_NAME: $PRIVATE_DOMAIN_NAME"
    echo "Full command: mc --insecure alias set mycloud \"${MINIO_URL}\" \"${MINIO_ROOT_USER}\" \"${MINIO_ROOT_PASSWORD}\""
    echo "mc version: $(mc --version)"
    echo "Current aliases: $(mc alias list)"
  fi

  [ "$status" -eq 0 ]
}
