#!/bin/bash

# Checks the pdns private DNS driver after a switch from coredns.
#
# prepare: creates a probe pod and an HTTPRoute whose hostname is in the private zone.
# measure: polls until the route's A record resolves against the pdns Service, and
#          prints the time from the CoreDNS prune to that first answer.
#
# Run it under `windsor exec --` so kubectl has the cluster context.
# Usage: pdns-check.sh prepare | measure [timeout_seconds]

set -eo pipefail

NAMESPACE=system-dns
PROBE_NAMESPACE=default
PROBE_POD=pdns-probe
ROUTE_NAME=pdns-ci
ZONE="${PRIVATE_DOMAIN:-test}"
HOST="${ROUTE_NAME}.${ZONE}"

now() { date +%s.%N; }

# resolves -> succeeds when the pdns Service answers an A query for HOST
resolves() {
  local ip
  ip=$(kubectl get svc pdns -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null) || return 1
  [ -n "$ip" ] || return 1
  kubectl exec -n "$PROBE_NAMESPACE" "$PROBE_POD" -- nslookup "$HOST" "$ip" 2>/dev/null | grep -q '^Name:'
}

# coredns_present -> succeeds while a CoreDNS Deployment exists in system-dns
coredns_present() {
  kubectl get deployments -n "$NAMESPACE" -o name 2>/dev/null | grep -q coredns
}

prepare() {
  kubectl run "$PROBE_POD" -n "$PROBE_NAMESPACE" --image=docker.io/library/busybox:1.37.0 --restart=Never -- sleep 3600
  kubectl wait -n "$PROBE_NAMESPACE" --for=condition=Ready "pod/$PROBE_POD" --timeout=180s

  kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${ROUTE_NAME}
  namespace: ${PROBE_NAMESPACE}
spec:
  parentRefs:
    - kind: Gateway
      name: internal
      namespace: system-gateway
      sectionName: web-https
  hostnames:
    - ${HOST}
  rules:
    - backendRefs:
        - kind: Service
          name: kubernetes
          port: 443
EOF

  if ! coredns_present; then
    echo "No CoreDNS Deployment in $NAMESPACE before the switch."
    exit 1
  fi
}

measure() {
  local timeout="${1:-900}"
  local start prune="" sync=""
  start=$(now)

  while true; do
    local t
    t=$(now)
    if [ -z "$prune" ] && ! coredns_present; then
      prune=$t
      echo "CoreDNS pruned after $(echo "$t - $start" | bc)s."
    fi
    if resolves; then
      sync=$(now)
      echo "$HOST answered by the pdns Service after $(echo "$sync - $start" | bc)s."
      break
    fi
    if [ "$(echo "$t - $start > $timeout" | bc)" = 1 ]; then
      echo "Timed out after ${timeout}s: $HOST never resolved against the pdns Service."
      kubectl get pods,jobs -n "$NAMESPACE" || true
      kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/instance=external-dns-private --tail=50 || true
      exit 1
    fi
    sleep 1
  done

  if [ -z "$prune" ]; then
    echo "CoreDNS was not pruned before the record resolved."
    exit 1
  fi

  local gap
  gap=$(echo "$sync - $prune" | bc)
  echo "Gap between the CoreDNS prune and the first pdns answer: ${gap}s (1s poll interval)."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "pdns switch: ${gap}s between the CoreDNS prune and the first pdns answer for \`$HOST\`." >> "$GITHUB_STEP_SUMMARY"
  fi
}

case "${1:-}" in
  prepare) prepare ;;
  measure) measure "${2:-}" ;;
  *) echo "Usage: $0 prepare | measure [timeout_seconds]" >&2; exit 2 ;;
esac
