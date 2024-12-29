#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Trivy Component Tests
# bats file_tags=security:vulns
#-----------------------------------------------------------------------------------------------------------------------

@test "Scans: Check Trivy pods are running in 'system-scans' namespace" {
  run check_pods_running "system-scans" "app.kubernetes.io/name=trivy-operator" 1
  [ "$status" -eq 0 ]
}

@test "Scans: Check services for Trivy" {
  run check_service_exists "system-scans" trivy-trivy-operator
  [ "$status" -eq 0 ]
}
