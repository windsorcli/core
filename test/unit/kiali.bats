#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Kiali Component Tests
# bats file_tags=network:service-mesh:kiali
#-----------------------------------------------------------------------------------------------------------------------

@test "Service Mesh: Check kiali pod" {
  check_pods_running "system-service-mesh" "app.kubernetes.io/name=kiali" 1
}

@test "Service Mesh: Check kiali-operator pod" {
  check_pods_running "system-service-mesh" "app.kubernetes.io/name=kiali-operator" 1
}

@test "Service Mesh: Check kiali service" {
  check_service_exists "system-service-mesh" "kiali"
}

@test "Service Mesh: Check kialis.kiali.io CRD version" {
  check_crd_version "kialis.kiali.io" "v1alpha1"
}
