#!/usr/bin/env bash
set -eou pipefail

# Path to SSL certificate, key, and trust store
SSL_CERT_PATH="/data/keycloak.crt"
SSL_KEY_PATH="/data/keycloak.key"
TRUST_STORE="/data/keycloak-truststore.jks"
TRUSTSTORE_PASSWORD="password"

# Keycloak variables
REALM_NAME="test-realm"
USER_NAME="test-user"
USER_PASSWORD="test"
GROUP_NAME="test-group"
CLIENT_NAME="test-client"

# Function to start Keycloak server with SSL
start_keycloak() {
  /opt/keycloak/bin/kc.sh start-dev \
    --https-certificate-file=$SSL_CERT_PATH \
    --https-certificate-key-file=$SSL_KEY_PATH &
  KEYCLOAK_PID=$!
}

# Function to wait for Keycloak to be ready
wait_for_keycloak() {
  sleep 10
}

# Function to log in to realm
login() {
  /opt/keycloak/bin/kcadm.sh config truststore --trustpass $TRUSTSTORE_PASSWORD $TRUST_STORE
  /opt/keycloak/bin/kcadm.sh config credentials \
    --server https://127.0.0.1:8443 \
    --realm master \
    --user admin \
    --password admin
}

# Function to get user ID
get_user_id() {
  /opt/keycloak/bin/kcadm.sh get users -r $REALM_NAME -q username=$USER_NAME --fields id --format csv --noquotes
}

# Function to get group ID
get_group_id() {
  /opt/keycloak/bin/kcadm.sh get groups -r $REALM_NAME -q name=$GROUP_NAME --fields id --format csv --noquotes
}

get_client_id() {
  /opt/keycloak/bin/kcadm.sh get clients -r $REALM_NAME -q clientId=$CLIENT_NAME --fields id --format csv --noquotes
}

get_client_secret() {
  /opt/keycloak/bin/kcadm.sh get "clients/$(get_client_id)/client-secret" -r $REALM_NAME --fields value --format csv --noquotes
}

# Function to create a test realm, user, group, and client
create_test_realm() {
  /opt/keycloak/bin/kcadm.sh create realms -s realm=$REALM_NAME -s enabled=true
  /opt/keycloak/bin/kcadm.sh create users -r $REALM_NAME -s username=$USER_NAME -s enabled=true
  /opt/keycloak/bin/kcadm.sh set-password -r $REALM_NAME --username $USER_NAME --new-password $USER_PASSWORD
  /opt/keycloak/bin/kcadm.sh create groups -r $REALM_NAME -s name=kube-admin

  /opt/keycloak/bin/kcadm.sh create clients -r $REALM_NAME \
    -s clientId=test-client \
    -s enabled=true \
    -s clientAuthenticatorType=client-secret \
    -s directAccessGrantsEnabled=true \
    -s 'redirectUris=["https://127.0.0.1:8443/app/*"]' \
    -s 'webOrigins=["https://10.5.0.2:8443"]'

  /opt/keycloak/bin/kcadm.sh update "users/$(get_user_id)/groups/$(get_group_id)" -r $REALM_NAME -n
}

report_credentials() {
  echo "Keycloak credentials:"
  echo "  Username: admin"
  echo "  Password: admin"
  echo "  Realm: master"
  echo "  URL: https://127.0.0.1:8443"
  echo "Test realm credentials:"
  echo "  Username: $USER_NAME"
  echo "  Password: $USER_PASSWORD"
  echo "  Realm: $REALM_NAME"
  echo "  URL: https://127.0.0.1:8443/auth/realms/$REALM_NAME"
  echo "Test client credentials:"
  echo "  Client ID: $(get_client_id)"
  echo "  Client Secret: $(get_client_secret)"
  echo "  URL: https://127.0.0.1:8443/app"
}

# Main execution
start_keycloak
wait_for_keycloak
login
create_test_realm
report_credentials

# Infinite loop to keep the script running as long as Keycloak is running
while kill -0 $KEYCLOAK_PID 2>/dev/null; do
  sleep 5
done

echo "Keycloak server stopped unexpectedly."
