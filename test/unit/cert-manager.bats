#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Cert-Manager Component Tests
# bats file_tags=certificates,baseline:core,baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "PKI: Check cert-manager pods" {
  check_pods_running "system-pki" "app=cert-manager" 1
}

@test "PKI: Check cert-manager service" {
  check_service_exists "system-pki" "cert-manager"
}

@test "PKI: Check cert-manager-webhook pods" {
  check_pods_running "system-pki" "app.kubernetes.io/component=webhook,app.kubernetes.io/instance=cert-manager" 1
}

@test "PKI: Check cert-manager-webhook service" {
  check_service_exists "system-pki" "cert-manager-webhook"
}

@test "PKI: Check certificaterequests.cert-manager.io CRD version" {
  check_crd_version "certificaterequests.cert-manager.io" "v1"
}

@test "PKI: Check certificates.cert-manager.io CRD version" {
  check_crd_version "certificates.cert-manager.io" "v1"
}

@test "PKI: Check challenges.acme.cert-manager.io CRD version" {
  check_crd_version "challenges.acme.cert-manager.io" "v1"
}

@test "PKI: Check clusterissuers.cert-manager.io CRD version" {
  check_crd_version "clusterissuers.cert-manager.io" "v1"
}

@test "PKI: Check issuers.cert-manager.io CRD version" {
  check_crd_version "issuers.cert-manager.io" "v1"
}

@test "PKI: Check orders.acme.cert-manager.io CRD version" {
  check_crd_version "orders.acme.cert-manager.io" "v1"
}

@test "PKI: Check that ClusterIssuers are ready" {
  run kubectl get clusterissuer private private-ca public -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
  [ "$status" -eq 0 ]
  [ "$output" == "True True True" ]
}

@test "PKI: Check that the 'private-ca' Certificate is ready in 'security' namespace" {
  run kubectl get certificate private-ca -n system-pki -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [ "$status" -eq 0 ]
  [ "$output" == "True" ]
}
