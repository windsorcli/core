#!/usr/bin/env bash
# Builds images/utils with scripts/apko-image.sh. The tag follows the locked kubectl version.
exec env IMAGE_NAME=utils VERSION_PACKAGE='^kubectl-[0-9]+\.[0-9]+$' "$(dirname "$0")/apko-image.sh" "$@"
