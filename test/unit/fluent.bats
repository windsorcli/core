#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Fluent Component Tests
# bats file_tags=monitoring:fluent
#-----------------------------------------------------------------------------------------------------------------------

@test "Monitoring: Check fluent-bit pods" {
  check_pods_running "system-telemetry" "app.kubernetes.io/name=fluent-bit" 2
}

@test "Monitoring: Check fluent-operator pods" {
  run check_pods_running "system-telemetry" "app.kubernetes.io/name=fluent-operator" 1
}

@test "Monitoring: Check fluentd pods" {
  run check_pods_running "system-observability" "app.kubernetes.io/name=fluentd" 1
}

@test "Monitoring: Check fluent-bit service" {
  check_service_exists "system-telemetry" "fluent-bit"
}

@test "Monitoring: Check fluentd service" {
  check_service_exists "system-observability" "fluentd"
}
