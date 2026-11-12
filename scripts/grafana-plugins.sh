#!/usr/bin/env bash
# Update the Grafana plugin image. The script downloads each plugin zip in
# images/grafana-plugins/Dockerfile and writes its SHA-256 into the Dockerfile. Then it
# sets the image tag in the grafana/quickwit HelmRelease patch. The tag is the first 12
# characters of the SHA-256 of the files in images/grafana-plugins, so each change to the
# image gets a new tag. CI pushes each tag that ghcr.io does not have yet.
#
#   scripts/grafana-plugins.sh             write the checksums and the tag
#   scripts/grafana-plugins.sh --write-tag write only the tag (no download)
#   scripts/grafana-plugins.sh --check     verify the tag; non-zero on drift (CI)
#   scripts/grafana-plugins.sh --tag       print the tag

set -euo pipefail

IMAGE_DIR="images/grafana-plugins"
DOCKERFILE="$IMAGE_DIR/Dockerfile"
IMAGE="ghcr.io/windsorcli/grafana-plugins"
IMAGE_RE="ghcr\\.io/windsorcli/grafana-plugins"
RELEASE="kustomize/observability/install/grafana/quickwit/patches/helm-release.yaml"
MODE="${1:-}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

# arg_value <name> -> the default value of ARG name in DOCKERFILE
arg_value() {
  sed -n "s/^ARG $1=//p" "$DOCKERFILE"
}

# write_checksums -> downloads the zip of each fetch line in DOCKERFILE and writes its
# SHA-256 into the ARG that the line names. A fetch line has the form
#   fetch <plugin-id> "<url with ${ARG} references>" "$<NAME>_SHA256"
write_checksums() {
  local line url sum_arg ref value sum
  grep -oE 'fetch [a-z0-9-]+ "[^"]+" "\$[A-Z0-9_]+"' "$DOCKERFILE" | while read -r line; do
    url=$(echo "$line" | cut -d'"' -f2)
    sum_arg=$(echo "$line" | cut -d'"' -f4 | tr -d '$')
    for ref in $(echo "$url" | grep -oE '\$\{[A-Z0-9_]+\}' | sort -u); do
      ref="${ref#\$\{}"
      ref="${ref%\}}"
      value=$(arg_value "$ref")
      if [ -z "$value" ]; then
        echo "error: $DOCKERFILE has no 'ARG $ref=' line" >&2
        exit 1
      fi
      url="${url//\$\{$ref\}/$value}"
    done
    curl -fsSL -o "$work/plugin.zip" "$url"
    sum=$(sha256sum "$work/plugin.zip" | cut -d' ' -f1)
    sed "s/^ARG ${sum_arg}=.*/ARG ${sum_arg}=${sum}/" "$DOCKERFILE" > "$work/Dockerfile"
    cat "$work/Dockerfile" > "$DOCKERFILE"
    echo "Set ${sum_arg}=${sum} from $url"
  done
}

# write_tag -> writes the tag for the current content of IMAGE_DIR into RELEASE
write_tag() {
  local have want
  have=$(release_tag)
  want=$(image_tag)
  sed "s#reference: ${IMAGE_RE}:${have}#reference: ${IMAGE}:${want}#" "$RELEASE" > "$work/release.yaml"
  cat "$work/release.yaml" > "$RELEASE"
  echo "Set ${IMAGE}:${want} in $RELEASE"
}

case "$MODE" in
  --tag)
    image_tag
    ;;
  --check)
    have=$(release_tag)
    want=$(image_tag)
    if [ "$have" != "$want" ]; then
      echo "error: $RELEASE uses ${IMAGE}:${have}, but $IMAGE_DIR builds ${IMAGE}:${want}" >&2
      echo "Run 'task grafana:plugins' and commit the change." >&2
      exit 1
    fi
    echo "Grafana plugin image tag ${want} is up to date"
    ;;
  --write-tag)
    write_tag
    ;;
  "")
    write_checksums
    write_tag
    ;;
  *)
    echo "usage: $0 [--write-tag|--check|--tag]" >&2
    exit 2
    ;;
esac
