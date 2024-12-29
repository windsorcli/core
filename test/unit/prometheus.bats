#!/usr/bin/env bats

setup() {
  BASE_DIR="$(dirname "$BATS_TEST_DIRNAME")"
  load "${BASE_DIR}/lib/utils.sh"
}

# Function to query Prometheus and check for the presence of a metric
query_and_check_metric() {
  local metric=$1
  local query_url="https://prometheus.${PRIVATE_DOMAIN_NAME}/api/v1/query?query=${metric}"
  # Execute the curl request
  local response=$(curl -s -G -k --data-urlencode "query=$metric" "$query_url")
  # Check if the metric is present using jq
  echo "$response" | jq -e ".data.result[].metric.__name__ | select(. == \"$metric\")" >/dev/null

  # If jq fails (i.e., the metric is not found), exit with a non-zero status to indicate failure
  if [ $? -ne 0 ]; then
    echo "Metric $metric not found or no data returned"
    return 1
  fi
}

#-----------------------------------------------------------------------------------------------------------------------
# Prometheus Component Tests
# bats file_tags=monitoring:prometheus
#-----------------------------------------------------------------------------------------------------------------------

@test "Telemetry: Check CRDs for kube-prometheus-stack" {
  run check_crd_version alertmanagerconfigs.monitoring.coreos.com v1alpha1
  [ "$status" -eq 0 ]

  run check_crd_version alertmanagers.monitoring.coreos.com v1
  [ "$status" -eq 0 ]

  run check_crd_version podmonitors.monitoring.coreos.com v1
  [ "$status" -eq 0 ]

  run check_crd_version probes.monitoring.coreos.com v1
  [ "$status" -eq 0 ]

  run check_crd_version prometheusagents.monitoring.coreos.com v1alpha1
  [ "$status" -eq 0 ]

  run check_crd_version prometheuses.monitoring.coreos.com v1
  [ "$status" -eq 0 ]

  run check_crd_version prometheusrules.monitoring.coreos.com v1
  [ "$status" -eq 0 ]

  run check_crd_version scrapeconfigs.monitoring.coreos.com v1alpha1
  [ "$status" -eq 0 ]

  run check_crd_version servicemonitors.monitoring.coreos.com v1
  [ "$status" -eq 0 ]

  run check_crd_version thanosrulers.monitoring.coreos.com v1
  [ "$status" -eq 0 ]
}

@test "Telemetry: Check kube-prometheus-stack pods are running in 'system-telemetry' namespace" {

  run check_pods_running system-telemetry "app.kubernetes.io/name=alertmanager" 1
  [ "$status" -eq 0 ]

  run check_pods_running system-telemetry "app.kubernetes.io/name=kube-state-metrics" 1
  [ "$status" -eq 0 ]

  run check_pods_running system-telemetry "app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator" 1
  [ "$status" -eq 0 ]

  run check_pods_running system-telemetry "app.kubernetes.io/name=prometheus-node-exporter" 2
  [ "$status" -eq 0 ]

  run check_pods_running system-telemetry "app.kubernetes.io/name=prometheus" 1
  [ "$status" -eq 0 ]
}

@test "Telemetry: Check services for kube-prometheus-stack" {
  run check_service_exists system-telemetry alertmanager-operated
  [ "$status" -eq 0 ]

  run check_service_exists system-telemetry kube-prometheus-stack-alertmanager 
  [ "$status" -eq 0 ]

  run check_service_exists system-telemetry kube-prometheus-stack-kube-state-metrics
  [ "$status" -eq 0 ]

  run check_service_exists system-telemetry kube-prometheus-stack-operator
  [ "$status" -eq 0 ]

  run check_service_exists system-telemetry kube-prometheus-stack-prometheus
  [ "$status" -eq 0 ]

  run check_service_exists system-telemetry kube-prometheus-stack-prometheus-node-exporter
  [ "$status" -eq 0 ]

  run check_service_exists system-telemetry prometheus-operated
  [ "$status" -eq 0 ]
}

@test "Telemetry: Check if https://prometheus.${PRIVATE_DOMAIN_NAME}/graph returns 200 OK" {
  # Send a request to the specified URL and store the HTTP status code
  status_code=$(curl -k -o /dev/null -s -w "%{http_code}\n" https://prometheus.${PRIVATE_DOMAIN_NAME}/graph)

  # Check if the status code is 200
  [ "$status_code" -eq 200 ]
}

@test "Telemetry: Verify presence of critical Prometheus metrics" {
  run query_and_check_metric "up"
  [ "$status" -eq 0 ]

  run query_and_check_metric "node_cpu_seconds_total"
  [ "$status" -eq 0 ]

  run query_and_check_metric "kube_pod_status_phase"
  [ "$status" -eq 0 ]

  run query_and_check_metric "kube_node_status_condition"
  [ "$status" -eq 0 ]

  run query_and_check_metric "gotk_reconcile_duration_seconds_bucket" 
  [ "$status" -eq 0 ]

  run query_and_check_metric "gotk_resource_info" 
  [ "$status" -eq 0 ]
}
