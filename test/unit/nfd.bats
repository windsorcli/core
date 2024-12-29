#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Node Feature Discovery Component Tests
# bats file_tags=baseline:core,baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "Node: Check nfd worker pods" {
  check_pods_running "system-node" "app=nfd-worker" 1
}

@test "Node: Check nfd master pods" {
  check_pods_running "system-node" "app=nfd-master" 1
}

@test "Node: Check nfd gc pods" {
  check_pods_running "system-node" "app=nfd-gc" 1
}

@test "Node: Check nodefeaturerules.nfd.k8s-sigs.io CRD version" {
  check_crd_version "nodefeaturerules.nfd.k8s-sigs.io" "v1alpha1"
}

@test "Node: Check nodefeatures.nfd.k8s-sigs.io CRD version" {
  check_crd_version "nodefeaturerules.nfd.k8s-sigs.io" "v1alpha1"
}
