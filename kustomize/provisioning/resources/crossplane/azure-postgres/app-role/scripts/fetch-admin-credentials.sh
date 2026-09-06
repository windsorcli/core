#!/usr/bin/env bash
# shellcheck disable=SC2154  # pg_* vars are Flux postBuild.substitute placeholders, not shell vars
set -euo pipefail

READY=$(kubectl get flexibleserver.dbforpostgresql.azure.upbound.io "${pg_instance_name}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "$READY" != "True" ]; then
  echo "${pg_instance_name} FlexibleServer not Ready yet, skipping this tick."
  touch /shared/skip
  exit 0
fi

kubectl get flexibleserver.dbforpostgresql.azure.upbound.io "${pg_instance_name}" \
  -o jsonpath='{.status.atProvider.fqdn}' > /shared/address
kubectl get flexibleserver.dbforpostgresql.azure.upbound.io "${pg_instance_name}" \
  -o jsonpath='{.spec.forProvider.administratorLogin}' > /shared/admin-username

kubectl get secret "${pg_instance_name}"-admin-credentials \
  -n system-provisioning -o jsonpath='{.data.password}' | base64 -d > /shared/admin-password

# Reuse the password already published, so a role that already exists
# doesn't get a new one every tick — an app reading this Secret via env
# var wouldn't see the change anyway. Only a fresh role gets a fresh one,
# independent of the admin password's own rotation.
EXISTING=$(kubectl get secret "${pg_instance_name}"-app-credentials \
  -n "${pg_target_namespace}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
if [ -n "$EXISTING" ]; then
  echo -n "$EXISTING" > /shared/app-password
else
  head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > /shared/app-password
  touch /shared/needs-password-set
fi
