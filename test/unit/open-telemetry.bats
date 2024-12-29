#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Open Telemetry Component Tests
# bats file_tags=monitoring:otel
#-----------------------------------------------------------------------------------------------------------------------

@test "Monitoring: Check opentelemetry-operator pods" {
  check_pods_running "monitoring" "app.kubernetes.io/name=opentelemetry-operator" 1
}

@test "Monitoring: Check otel-logs-collector pods" {
  run check_pods_running "monitoring" "app.kubernetes.io/name=otel-logs-collector" 1
}

@test "Monitoring: Check opentelemetry-operator service" {
  check_service_exists "monitoring" "opentelemetry-operator"
}

@test "Monitoring: Check opentelemetry-operator-webhook service" {
  check_service_exists "monitoring" "opentelemetry-operator-webhook"
}

@test "Monitoring: Check otel-logs-collector-monitoring service" {
  check_service_exists "monitoring" "otel-logs-collector-monitoring"
}
