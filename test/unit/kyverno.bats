#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Kyverno Component Tests
# bats file_tags=security:compliance,baseline:core,baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "Policy: Check kyverno-admission-controller pods" {
  check_pods_running "system-policy" "app.kubernetes.io/component=admission-controller,app.kubernetes.io/instance=kyverno" 1
}

@test "Policy: Check kyverno-background-controller pods" {
  check_pods_running "system-policy" "app.kubernetes.io/component=background-controller,app.kubernetes.io/instance=kyverno" 1
}

@test "Policy: Check kyverno-cleanup-controller pods" {
  check_pods_running "system-policy" "app.kubernetes.io/component=cleanup-controller,app.kubernetes.io/instance=kyverno" 1
}

@test "Policy: Check kyverno-reports-controller pods" {
  check_pods_running "system-policy" "app.kubernetes.io/component=reports-controller,app.kubernetes.io/instance=kyverno" 1
}

@test "Policy: Check kyverno-background-controller-metrics service" {
  check_service_exists "system-policy" "kyverno-background-controller-metrics"
}

@test "Policy: Check kyverno-cleanup-controller service" {
  check_service_exists "system-policy" "kyverno-cleanup-controller"
}

@test "Policy: Check kyverno-cleanup-controller-metrics service" {
  check_service_exists "system-policy" "kyverno-cleanup-controller-metrics"
}

@test "Policy: Check kyverno-reports-controller-metrics service" {
  check_service_exists "system-policy" "kyverno-reports-controller-metrics"
}

@test "Policy: Check kyverno-svc service" {
  check_service_exists "system-policy" "kyverno-svc"
}

@test "Policy: Check kyverno-svc-metrics service" {
  check_service_exists "system-policy" "kyverno-svc-metrics"
}

@test "Policy: Check admissionreports.kyverno.io CRD version" {
  check_crd_version "admissionreports.kyverno.io" "v1alpha2"
}

@test "Policy: Check backgroundscanreports.kyverno.io CRD version" {
  check_crd_version "backgroundscanreports.kyverno.io" "v1alpha2"
}

@test "Policy: Check cleanuppolicies.kyverno.io CRD version" {
  check_crd_version "cleanuppolicies.kyverno.io" "v2beta1"
}

@test "Policy: Check clusteradmissionreports.kyverno.io CRD version" {
  check_crd_version "clusteradmissionreports.kyverno.io" "v1alpha2"
}

@test "Policy: Check clusterbackgroundscanreports.kyverno.io CRD version" {
  check_crd_version "clusterbackgroundscanreports.kyverno.io" "v1alpha2"
}

@test "Policy: Check clustercleanuppolicies.kyverno.io CRD version" {
  check_crd_version "clustercleanuppolicies.kyverno.io" "v2beta1"
}

@test "Policy: Check clusterpolicies.kyverno.io CRD version" {
  check_crd_version "clusterpolicies.kyverno.io" "v1"
}

@test "Policy: Check policies.kyverno.io CRD version" {
  check_crd_version "policies.kyverno.io" "v1"
}

@test "Policy: Check policyexceptions.kyverno.io CRD version" {
  check_crd_version "policyexceptions.kyverno.io" "v2beta1"
}

@test "Policy: Check updaterequests.kyverno.io CRD version" {
  check_crd_version "updaterequests.kyverno.io" "v1beta1"
}
