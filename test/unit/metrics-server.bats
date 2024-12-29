#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Metrics Server Component Tests
# bats file_tags=monitoring:cluster,baseline:core,baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "Telemetry: Check metrics-server pods" {
  check_pods_running "system-telemetry" "app.kubernetes.io/name=metrics-server" 1
}

@test "Telemetry: Check if Metrics Server responds with node metrics" {
  run kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"
  [ "$status" -eq 0 ]
  [ "${#output}" -gt 0 ]
}

@test "Telemetry: Check if Metrics Server responds with pod metrics" {
  run kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods"
  [ "$status" -eq 0 ]
  [ "${#output}" -gt 0 ]
}
