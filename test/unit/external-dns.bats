#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# ExternalDNS Component Tests
# bats file_tags=baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "DNS: Check external-dns pods" {
  # bats test_tags=network:dns
  check_pods_running "system-dns" "app.kubernetes.io/name=external-dns" 2
}

@test "DNS: Check external-dns-private service" {
  # bats test_tags=network:dns
  check_service_exists "system-dns" "external-dns-private"
}

@test "DNS: Check external-dns-public service" {
  # bats test_tags=network:dns
  check_service_exists "system-dns" "external-dns-public"
}
