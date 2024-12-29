#!/usr/bin/env bash
set -eou pipefail

# This script generates a self-signed certificate for Keycloak and a Java trust store. This script has already been
# executed, and the generated files are in the repository. They should last for 10 years, and expire on 2033-12-10,
# assuming any of us make it until then. If you want to generate new certificates, you can run this script again. You'll
# need to have Java installed as it's necessary to generate the trust store.

# Determine script's directory and set output directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
OUTPUT_DIR="$SCRIPT_DIR/../data/keycloak"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Variables
DAYS=3650
TRUSTSTORE_PASSWORD="password"
KEYCLOAK_DOCKER_IP="10.5.3.3"

# Generate CA key and certificate
openssl genrsa -out "$OUTPUT_DIR/ca.key" 2048
openssl req -x509 -new -nodes -key "$OUTPUT_DIR/ca.key" -sha256 -days $DAYS -out "$OUTPUT_DIR/ca.crt" -subj "/CN=Acme Internal CA"

# Generate Keycloak server key
openssl genrsa -out "$OUTPUT_DIR/keycloak.key" 2048

# Create OpenSSL config file for SANs
cat > "$OUTPUT_DIR/openssl.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = 127.0.0.1

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = keycloak
IP.1 = 127.0.0.1
IP.2 = ${KEYCLOAK_DOCKER_IP}
EOF

# Generate Keycloak server certificate signing request with SANs
openssl req -new -key "$OUTPUT_DIR/keycloak.key" -out "$OUTPUT_DIR/keycloak.csr" -config "$OUTPUT_DIR/openssl.cnf"

# Sign the server certificate with the CA
openssl x509 -req -in "$OUTPUT_DIR/keycloak.csr" -CA "$OUTPUT_DIR/ca.crt" -CAkey "$OUTPUT_DIR/ca.key" -CAcreateserial -out "$OUTPUT_DIR/keycloak.crt" -days $DAYS -sha256 -extensions v3_req -extfile "$OUTPUT_DIR/openssl.cnf"

# Create a trust store and import the CA certificate
keytool -import -trustcacerts -alias "keycloak" -file "$OUTPUT_DIR/ca.crt" -keystore "$OUTPUT_DIR/keycloak-truststore.jks" -storepass "$TRUSTSTORE_PASSWORD" -noprompt

# Clean up
rm "$OUTPUT_DIR/keycloak.csr"
rm "$OUTPUT_DIR/ca.srl"
rm "$OUTPUT_DIR/openssl.cnf"
