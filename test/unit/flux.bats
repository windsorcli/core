#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

#-----------------------------------------------------------------------------------------------------------------------
# Flux Tests
# bats file_tags=gitops:flux
#-----------------------------------------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------------------------------------
# Capacitor
#-----------------------------------------------------------------------------------------------------------------------

# Capacitor is presently disabled by default due to a start up issue. Also, it is questionable
# as to whether it's relevant as there are better visualization tools available.

# @test "Flux-System: Check capacitor pods" {
#   check_pods_running "system-gitops" "app.kubernetes.io/instance=capacitor" 1
# }

# @test "Flux-System: Check capacitor service" {
#   check_service_exists "system-gitops" "capacitor"
# }

# @test "Flux-System: Check if https://capacitor.${PRIVATE_DOMAIN_NAME} returns 200 OK" {
#   # Send a request to the specified URL and store the HTTP status code
#   status_code=$(curl -k -o /dev/null -s -w "%{http_code}\n" https://capacitor.${PRIVATE_DOMAIN_NAME})

#   # Check if the status code is 200
#   [ "$status_code" -eq 200 ]
# }

@test "GitOps: Check CRDs for flux-system" {

  run check_crd_version alerts.notification.toolkit.fluxcd.io v1beta3
  [ "$status" -eq 0 ]

  run check_crd_version buckets.source.toolkit.fluxcd.io v1beta2
  [ "$status" -eq 0 ]

  run check_crd_version gitrepositories.source.toolkit.fluxcd.io v1
  [ "$status" -eq 0 ]

  run check_crd_version helmcharts.source.toolkit.fluxcd.io v1
  [ "$status" -eq 0 ]

  run check_crd_version helmreleases.helm.toolkit.fluxcd.io v2
  [ "$status" -eq 0 ]

  run check_crd_version helmrepositories.source.toolkit.fluxcd.io v1
  [ "$status" -eq 0 ]

  run check_crd_version imagepolicies.image.toolkit.fluxcd.io v1beta2
  [ "$status" -eq 0 ]

  run check_crd_version imagerepositories.image.toolkit.fluxcd.io v1beta2
  [ "$status" -eq 0 ]

  run check_crd_version imageupdateautomations.image.toolkit.fluxcd.io v1beta1
  [ "$status" -eq 0 ]

  run check_crd_version kustomizations.kustomize.toolkit.fluxcd.io v1
  [ "$status" -eq 0 ]

  run check_crd_version ocirepositories.source.toolkit.fluxcd.io v1beta2
  [ "$status" -eq 0 ]

  run check_crd_version providers.notification.toolkit.fluxcd.io v1beta3
  [ "$status" -eq 0 ]

  run check_crd_version receivers.notification.toolkit.fluxcd.io v1
  [ "$status" -eq 0 ]
}

@test "GitOps: Check pods for flux-system" {

  run check_pods_running "system-gitops" "app=helm-controller" 1
  [ "$status" -eq 0 ]

  run check_pods_running "system-gitops" "app=image-automation-controller" 1
  [ "$status" -eq 0 ]

  run check_pods_running "system-gitops" "app=image-reflector-controller" 1
  [ "$status" -eq 0 ]

  run check_pods_running "system-gitops" "app=kustomize-controller" 1
  [ "$status" -eq 0 ]

  run check_pods_running "system-gitops" "app=notification-controller" 1
  [ "$status" -eq 0 ]

  run check_pods_running "system-gitops" "app=source-controller" 1
  [ "$status" -eq 0 ]
}

@test "GitOps: Check services for flux-system" {

  run check_service_exists "system-gitops" notification-controller
  [ "$status" -eq 0 ]

  run check_service_exists "system-gitops" source-controller
  [ "$status" -eq 0 ]

  run check_service_exists "system-gitops" webhook-receiver
  [ "$status" -eq 0 ]
}
