#!/usr/bin/env bash
# Builds images/keycloak-config-cli with scripts/apko-image.sh. The tag follows the locked keycloak-config-cli version.
exec env IMAGE_NAME=keycloak-config-cli VERSION_PACKAGE='^keycloak-config-cli$' "$(dirname "$0")/apko-image.sh" "$@"
