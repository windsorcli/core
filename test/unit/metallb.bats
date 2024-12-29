#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Metallb Component Tests
# bats file_tags=network:metal,platform:metal
#-----------------------------------------------------------------------------------------------------------------------

@test "LB: Check metallb-controller pods" {
  cd "${BASE_DIR}/../kustomize/lb/tests/metallb"
  chainsaw test --test-file controller-running-test.yaml
}

@test "LB: Check metallb-speaker pods" {
  cd "${BASE_DIR}/../kustomize/lb/tests/metallb"
  chainsaw test --test-file speaker-running-test.yaml
}

@test "LB: Check metallb-webhook-service service" {
  check_service_exists "system-lb" "metallb-webhook-service"
}

@test "LB: Check bfdprofiles.metallb.io CRD version" {
  check_crd_version "bfdprofiles.metallb.io" "v1beta1"
}

@test "LB: Check bgpadvertisements.metallb.io CRD version" {
  check_crd_version "bgpadvertisements.metallb.io" "v1beta1"
}

@test "LB: Check bgppeers.metallb.io CRD version" {
  check_crd_version "bgppeers.metallb.io" "v1beta2"
}

@test "LB: Check communities.metallb.io CRD version" {
  check_crd_version "communities.metallb.io" "v1beta1"
}

@test "LB: Check ipaddresspools.metallb.io CRD version" {
  check_crd_version "ipaddresspools.metallb.io" "v1beta1"
}

@test "LB: Check l2advertisements.metallb.io CRD version" {
  check_crd_version "l2advertisements.metallb.io" "v1beta1"
}
