#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Trust-Manager Component Tests
# bats file_tags=trust,baseline:core,baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "Trust: Check trust-manager-webhook pods" {
  check_pods_running "system-pki-trust" "app.kubernetes.io/instance=trust-manager" 1
}

@test "Trust: Check trust-manager service" {
  check_service_exists "system-pki-trust" "trust-manager"
}

@test "Trust: Check trust-manager-metrics service" {
  check_service_exists "system-pki-trust" "trust-manager-metrics"
}

@test "Trust: Check bundles.trust.cert-manager.io CRD version" {
  check_crd_version "bundles.trust.cert-manager.io" "v1alpha1"
}

@test "Trust: Check 'private-ca' ConfigMap exists in system-observability namespace" {
  run kubectl get configmap private-ca -n system-observability
  [ "$status" -eq 0 ]
}
