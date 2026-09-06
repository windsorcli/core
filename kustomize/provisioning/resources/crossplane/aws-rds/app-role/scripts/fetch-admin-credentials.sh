#!/usr/bin/env bash
set -euo pipefail

READY=$(kubectl get instance.rds.aws.upbound.io ${pg_instance_name} \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "$READY" != "True" ]; then
  echo "${pg_instance_name} Instance not Ready yet, skipping this tick."
  touch /shared/skip
  exit 0
fi

kubectl get instance.rds.aws.upbound.io ${pg_instance_name} \
  -o jsonpath='{.status.atProvider.address}' > /shared/address

SECRET_ARN=$(kubectl get instance.rds.aws.upbound.io ${pg_instance_name} \
  -o jsonpath='{.status.atProvider.masterUserSecret[0].secretArn}')

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
  --query SecretString --output text)
echo "$SECRET_JSON" | jq -r '.username' > /shared/admin-username
echo "$SECRET_JSON" | jq -r '.password' > /shared/admin-password

# Reuse the password already published, so a role that already exists
# doesn't get a new one every tick — an app reading this Secret via env
# var wouldn't see the change anyway. Only a fresh role gets a fresh one,
# independent of the admin password's own AWS-managed rotation schedule.
EXISTING=$(kubectl get secret ${pg_instance_name}-app-credentials \
  -n ${pg_target_namespace} -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
if [ -n "$EXISTING" ]; then
  echo -n "$EXISTING" > /shared/app-password
else
  head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > /shared/app-password
  touch /shared/needs-password-set
fi
