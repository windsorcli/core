#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Istio Component Tests
# bats file_tags=network:service-mesh,baseline:core,baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "Service Mesh: Check istio-private-gateway pods" {
  check_pods_running "system-ingress" "app=istio-private-gateway-controller" 1
}

@test "Service Mesh: Check istio-public-gateway-controller pods" {
  check_pods_running "system-ingress" "app=istio-public-gateway-controller" 1
}

@test "Service Mesh: Check istio-private-gateway-controller service" {
  check_service_exists "system-ingress" "istio-private-gateway-controller"
}

@test "Service Mesh: Check istio-public-gateway-controller  service" {
  check_service_exists "system-ingress" "istio-public-gateway-controller"
}

@test "Service Mesh: Check istiod pods" {
  check_pods_running "system-service-mesh" "app=istiod" 1
}

@test "Service Mesh: Check istiod service" {
  check_service_exists "system-service-mesh" "istiod"
}

@test "Service Mesh: Check authorizationpolicies.security.istio.io CRD version" {
  check_crd_version "authorizationpolicies.security.istio.io" "v1beta1"
}

@test "Service Mesh: Check destinationrules.networking.istio.io CRD version" {
  check_crd_version "destinationrules.networking.istio.io" "v1beta1"
}

@test "Service Mesh: Check envoyfilters.networking.istio.io CRD version" {
  check_crd_version "envoyfilters.networking.istio.io" "v1alpha3"
}

@test "Service Mesh: Check gateways.networking.istio.io CRD version" {
  check_crd_version "gateways.networking.istio.io" "v1beta1"
}

@test "Service Mesh: Check peerauthentications.security.istio.io CRD version" {
  check_crd_version "peerauthentications.security.istio.io" "v1beta1"
}

@test "Service Mesh: Check proxyconfigs.networking.istio.io CRD version" {
  check_crd_version "proxyconfigs.networking.istio.io" "v1beta1"
}

@test "Service Mesh: Check requestauthentications.security.istio.io CRD version" {
  check_crd_version "requestauthentications.security.istio.io" "v1beta1"
}

@test "Service Mesh: Check serviceentries.networking.istio.io CRD version" {
  check_crd_version "serviceentries.networking.istio.io" "v1beta1"
}

@test "Service Mesh: Check sidecars.networking.istio.io CRD version" {
  check_crd_version "sidecars.networking.istio.io" "v1beta1"
}

@test "Service Mesh: Check telemetries.telemetry.istio.io CRD version" {
  check_crd_version "telemetries.telemetry.istio.io" "v1alpha1"
}

@test "Service Mesh: Check virtualservices.networking.istio.io CRD version" {
  check_crd_version "virtualservices.networking.istio.io" "v1beta1"
}

@test "Service Mesh: Check wasmplugins.extensions.istio.io CRD version" {
  check_crd_version "wasmplugins.extensions.istio.io" "v1alpha1"
}

@test "Service Mesh: Check workloadentries.networking.istio.io CRD version" {
  check_crd_version "workloadentries.networking.istio.io" "v1beta1"
}

@test "Service Mesh: Check workloadgroups.networking.istio.io CRD version" {
  check_crd_version "workloadgroups.networking.istio.io" "v1beta1"
}
