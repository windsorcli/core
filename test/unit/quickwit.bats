#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Quickwit Component Tests
# bats file_tags=monitoring:quickwit
#-----------------------------------------------------------------------------------------------------------------------

@test "Observability: Check quickwit controller pods" {
  check_pods_running "system-observability" "app.kubernetes.io/component=control-plane,app.kubernetes.io/instance=quickwit" 1
}

@test "Observability: Check quickwit indexer pods" {
  check_pods_running "system-observability" "app.kubernetes.io/component=indexer,app.kubernetes.io/instance=quickwit" 1
}

@test "Observability: Check quickwit janitor pods" {
  check_pods_running "system-observability" "app.kubernetes.io/component=janitor,app.kubernetes.io/instance=quickwit" 1
}

@test "Observability: Check quickwit metastore pods" {
  check_pods_running "system-observability" "app.kubernetes.io/component=metastore,app.kubernetes.io/instance=quickwit" 1
}

@test "Observability: Check quickwit searcher pods" {
  check_pods_running "system-observability" "app.kubernetes.io/component=searcher,app.kubernetes.io/instance=quickwit" 1
}

@test "Observability: Check quickwit-control-plane service" {
  check_service_exists "system-observability" "quickwit-control-plane"
}

@test "Observability: Check quickwit-headless service" {
  check_service_exists "system-observability" "quickwit-headless"
}

@test "Observability: Check quickwit-indexer service" {
  check_service_exists "system-observability" "quickwit-indexer"
}

@test "Observability: Check quickwit-janitor service" {
  check_service_exists "system-observability" "quickwit-janitor"
}

@test "Observability: Check quickwit-metastore service" {
  check_service_exists "system-observability" "quickwit-metastore"
}

@test "Observability: Check quickwit-searcher service" {
  check_service_exists "system-observability" "quickwit-searcher"
}
