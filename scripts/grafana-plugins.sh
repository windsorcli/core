#!/usr/bin/env bash
# Set the tag of the Grafana plugin image in the Grafana HelmRelease. The tag is the
# first 12 characters of the SHA-256 of the files in images/grafana-plugins, so each
# change to the image gets a new tag. CI pushes each tag that ghcr.io does not have yet.
#
#   scripts/grafana-plugins.sh           write the tag into the HelmRelease
#   scripts/grafana-plugins.sh --check   verify the tag; non-zero on drift (CI)
#   scripts/grafana-plugins.sh --tag     print the tag

set -euo pipefail

IMAGE_DIR="images/grafana-plugins"
IMAGE="ghcr.io/windsorcli/grafana-plugins"
IMAGE_RE="ghcr\\.io/windsorcli/grafana-plugins"
RELEASE="kustomize/observability/install/grafana/helm-release.yaml"
MODE="${1:-}"

# image_tag -> the tag for the current content of IMAGE_DIR
image_tag() {
  (cd "$IMAGE_DIR" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) \
    | sha256sum | cut -c1-12
}

# release_tag -> the tag of IMAGE in RELEASE, or an error when the line is missing
release_tag() {
  local tag
  tag=$(grep -oE "reference: ${IMAGE_RE}:[0-9a-f]+" "$RELEASE" | sed 's/.*://') || true
  if [ -z "$tag" ]; then
    echo "error: no 'reference: ${IMAGE}:<tag>' line in $RELEASE" >&2
    exit 1
  fi
  echo "$tag"
}

want=$(image_tag)

case "$MODE" in
  --tag)
    echo "$want"
    ;;
  --check)
    have=$(release_tag)
    if [ "$have" != "$want" ]; then
      echo "error: $RELEASE uses ${IMAGE}:${have}, but $IMAGE_DIR builds ${IMAGE}:${want}" >&2
      echo "Run 'task grafana:plugins' and commit the change." >&2
      exit 1
    fi
    echo "Grafana plugin image tag ${want} is up to date"
    ;;
  "")
    have=$(release_tag)
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    sed "s#reference: ${IMAGE_RE}:${have}#reference: ${IMAGE}:${want}#" "$RELEASE" > "$tmp"
    cat "$tmp" > "$RELEASE"
    echo "Set ${IMAGE}:${want} in $RELEASE"
    ;;
  *)
    echo "usage: $0 [--check|--tag]" >&2
    exit 2
    ;;
esac
