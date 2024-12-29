#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"

  DNS_SERVER_IP="10.5.255.200"
  PRIVATE_TLD=${PRIVATE_TLD:-"test"}
  PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME:-"private.test"}
  PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME:-"public.test"}
}

#-----------------------------------------------------------------------------------------------------------------------
# CoreDNS Component Tests
# bats file_tags=baseline:full
#-----------------------------------------------------------------------------------------------------------------------

@test "DNS: Check coredns pods" {
  # bats test_tags=network:dns
  check_pods_running "system-dns" "app.kubernetes.io/name=coredns" 1
}

@test "DNS: Check etcd-coredns pods" {
  # bats test_tags=network:private-zone
  check_pods_running "system-dns" "app.kubernetes.io/component=etcd" 3
}

@test "DNS: Check coredns service" {
  # bats test_tags=network:dns
  check_service_exists "system-dns" "coredns"
}

@test "DNS: Check etcd-coredns service" {
  # bats test_tags=network:private-zone
  check_service_exists "system-dns" "etcd-coredns"
}

@test "DNS: Check ingress-nginx-udp pod" {
  # bats test_tags=network:dns
  check_pods_running "system-dns" "app.kubernetes.io/instance=ingress-nginx-coredns" 1
}

@test "DNS: Check ingress-nginx-coredns-controller service" {
  # bats test_tags=network:private-zone
  check_service_exists "system-dns" "ingress-nginx-coredns-controller"
}

@test "DNS: Check ingress-nginx-coredns-controller-admission service" {
  # bats test_tags=network:private-zone
  check_service_exists "system-dns" "ingress-nginx-coredns-controller-admission"
}

@test "DNS: Dig query for A record of ${PRIVATE_DOMAIN_NAME}" {
  # bats test_tags=network:private-zone
  run dig @${DNS_SERVER_IP} A ${PRIVATE_DOMAIN_NAME}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"${PRIVATE_DOMAIN_NAME}."* ]]
  [[ "$output" == *"10.5.255.201"* ]]
}

@test "DNS: Dig query for A record of ${PUBLIC_DOMAIN_NAME}" {
  # bats test_tags=network:private-zone
  run dig @${DNS_SERVER_IP} A ${PUBLIC_DOMAIN_NAME}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"${PUBLIC_DOMAIN_NAME}."* ]]
  [[ "$output" == *"10.5.255.202"* ]]
}

@test "DNS resolution for gcr.${PRIVATE_TLD}" {
  run dig @${DNS_SERVER_IP} A gcr.${PRIVATE_TLD}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"gcr.${PRIVATE_TLD}."* ]]
}

@test "DNS resolution for ghcr.${PRIVATE_TLD}" {
  run dig @${DNS_SERVER_IP} A ghcr.${PRIVATE_TLD}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"ghcr.${PRIVATE_TLD}."* ]]
}

@test "DNS resolution for registry-1.docker.${PRIVATE_TLD}" {
  run dig @${DNS_SERVER_IP} A registry-1.docker.${PRIVATE_TLD}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"registry-1.docker.${PRIVATE_TLD}."* ]]
}

@test "DNS resolution for registry.k8s.${PRIVATE_TLD}" {
  run dig @${DNS_SERVER_IP} A registry.k8s.${PRIVATE_TLD}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"registry.k8s.${PRIVATE_TLD}."* ]]
}

@test "DNS resolution for registry.${PRIVATE_TLD}" {
  run dig @${DNS_SERVER_IP} A registry.${PRIVATE_TLD}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"registry.${PRIVATE_TLD}."* ]]
}

@test "DNS resolution for git.${PRIVATE_TLD}" {
  run dig @${DNS_SERVER_IP} A git.${PRIVATE_TLD}
  [ "$status" -eq 0 ]
  [[ "$output" == *";; ANSWER SECTION:"* ]]
  [[ "$output" == *"git.${PRIVATE_TLD}."* ]]
}
