#!/usr/bin/env bash

# Function to check pod count
check_pods_running() {
  local actual_count
  local namespace=$1
  local label_selector=$2
  local expected_count=$3
  
  actual_count=$(kubectl get pods -n "$namespace" -l "$label_selector" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)

  [ "$actual_count" -eq "$expected_count" ]
}

# Function to check service configuration
check_service_exists() {
  local namespace=$1
  local service=$2
  kubectl get service "$service" -n "$namespace" &> /dev/null
}

# Function to check CRD version
check_crd_version() {
  local crd=$1
  local version_to_check=$2
  local served_versions
  served_versions=$(kubectl get crd "$crd" -o jsonpath="{.spec.versions[?(@.served==true)].name}")

  if [[ -z "$served_versions" ]]; then
    echo "No served versions found for CRD $crd"
    return 1
  fi

  for version in $served_versions; do
    if [[ "$version" == "$version_to_check" ]]; then
      echo "Version $version_to_check is served for CRD $crd"
      return 0
    fi
  done

  echo "Version $version_to_check is not served for CRD $crd"
  return 1
}

retry_until_success() {
  local url=$1
  local max_attempts=5
  local count=0

  until [[ "$(curl -k -s --max-time 2 -o /dev/null -w '%{http_code}' "$url")" == "200" ]]; do
    count=$((count + 1))
    if [ "$count" -ge "$max_attempts" ]; then
      echo "Failed after $max_attempts attempts."
      curl -k -s --max-time 2 -o /dev/null -w '%{http_code}' "$url"
      return 1
    fi
    sleep 20
  done
}
