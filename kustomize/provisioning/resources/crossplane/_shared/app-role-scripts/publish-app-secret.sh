#!/usr/bin/env bash
set -euo pipefail

if [ -f /shared/skip ]; then
  echo "Skipping, nothing to publish this tick."
  exit 0
fi

kubectl create secret generic ${pg_instance_name}-app-credentials \
  -n ${pg_target_namespace} \
  --from-literal=username="${pg_database_name}_app" \
  --from-literal=password="$(cat /shared/app-password)" \
  --dry-run=client -o yaml | kubectl apply -f -
