#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Grafana Component Tests
# bats file_tags=monitoring:grafana
#-----------------------------------------------------------------------------------------------------------------------

@test "Observability Check grafana pods are running in 'system-observability' namespace" {
  run check_pods_running system-observability "app.kubernetes.io/name=grafana" 1
  [ "$status" -eq 0 ]
}

@test "Observability Check services for grafana" {
  run check_service_exists system-observability grafana
  [ "$status" -eq 0 ]
}

@test "Observability Check if https://grafana.${PRIVATE_DOMAIN_NAME}/login returns 200 OK" {
  # Send a request to the specified URL and store the HTTP status code
  status_code=$(curl -k -o /dev/null -s -w "%{http_code}\n" https://grafana.${PRIVATE_DOMAIN_NAME}/login)

  # Check if the status code is 200
  [ "$status_code" -eq 200 ]
}
