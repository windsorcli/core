#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Vector Component Tests
# bats file_tags=monitoring:vector
#-----------------------------------------------------------------------------------------------------------------------

@test "Monitoring: Check vector pods" {
  check_pods_running "monitoring" "app.kubernetes.io/instance=vector" 2
}

@test "Monitoring: Check vector-aggregator pods" {
  check_pods_running "monitoring" "app.kubernetes.io/instance=vector-aggregator" 1
}

@test "Monitoring: Check vector service" {
  check_service_exists "monitoring" "vector"
}

@test "Monitoring: Check vector-aggregator service" {
  check_service_exists "monitoring" "vector-aggregator"
}

@test "Monitoring: Check vector-aggregator-headless service" {
  check_service_exists "monitoring" "vector-aggregator-headless"
}

@test "Monitoring: Check vector-headless service" {
  check_service_exists "monitoring" "vector-headless"
}
