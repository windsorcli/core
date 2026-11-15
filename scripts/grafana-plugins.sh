#!/usr/bin/env bash
# Writes each plugin checksum into images/grafana-plugins/Dockerfile, then sets the tag from VERSION and the digest in the quickwit patch.
#
#   scripts/grafana-plugins.sh                   write the checksums, then the tag and digest
#   scripts/grafana-plugins.sh --write-checksums write only the checksums
#   scripts/grafana-plugins.sh --write-ref       write only the tag and digest (no download)
#   scripts/grafana-plugins.sh --check           verify the reference uses VERSION; non-zero on drift (CI)
#   scripts/grafana-plugins.sh --tag             print the version
#   scripts/grafana-plugins.sh --digest          print the digest that the reference pins
#   scripts/grafana-plugins.sh --build <dir>     build <dir>/image.tar and print its digest
#   scripts/grafana-plugins.sh --push <ref>      build and push the image to <ref>

set -euo pipefail

IMAGE_DIR="images/grafana-plugins"
DOCKERFILE="$IMAGE_DIR/Dockerfile"
VERSION_FILE="$IMAGE_DIR/VERSION"
BUILDER_FILE="$IMAGE_DIR/builder.yaml"
IMAGE="ghcr.io/windsorcli/grafana-plugins"
IMAGE_RE="ghcr\\.io/windsorcli/grafana-plugins"
REF_RE="${IMAGE_RE}:[0-9A-Za-z._-]+@sha256:[0-9a-f]{64}"
RELEASE="kustomize/observability/install/grafana/quickwit/patches/helm-release.yaml"
MODE="${1:-}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# image_tag -> the semver in VERSION_FILE, or an error when the file has none
image_tag() {
  local version
  version=$(tr -d '[:space:]' < "$VERSION_FILE")
  if ! echo "$version" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "error: $VERSION_FILE MUST hold a semver like 1.2.3, not '$version'" >&2
    exit 1
  fi
  echo "$version"
}

# release_ref -> the IMAGE reference in RELEASE, or an error when it has no tag and digest
release_ref() {
  local ref
  ref=$(grep -oE "reference: ${REF_RE}" "$RELEASE" | sed 's/^reference: //') || true
  if [ -z "$ref" ]; then
    echo "error: no 'reference: ${IMAGE}:<tag>@sha256:<digest>' line in $RELEASE" >&2
    exit 1
  fi
  echo "$ref"
}

# arg_value <name> -> the default value of ARG name in DOCKERFILE
arg_value() {
  sed -n "s/^ARG $1=//p" "$DOCKERFILE"
}

# builder -> the name of a buildx builder that runs the BuildKit image in BUILDER_FILE, created when missing
builder() {
  local buildkit name
  buildkit=$(sed -n 's/^image: *\([^ ]*\).*/\1/p' "$BUILDER_FILE")
  name="windsorcli-$(printf '%s' "$buildkit" | sha256sum | cut -c1-12)"
  if ! docker buildx inspect "$name" >/dev/null 2>&1; then
    docker buildx create --name "$name" --driver docker-container --driver-opt "image=$buildkit" >/dev/null
  fi
  echo "$name"
}

# buildx <output> -> builds IMAGE_DIR for both platforms into the buildx output
buildx() {
  local name
  name=$(builder)
  SOURCE_DATE_EPOCH=0 docker buildx build --builder "$name" \
    --platform linux/amd64,linux/arm64 --provenance=false --sbom=false \
    --label org.opencontainers.image.source=https://github.com/windsorcli/core \
    --output "$1" "$IMAGE_DIR" >"$work/build.log" 2>&1 || {
    cat "$work/build.log" >&2
    exit 1
  }
}

# build <dir> -> builds <dir>/image.tar and prints its index digest
build() {
  mkdir -p "$1"
  buildx "type=oci,dest=$1/image.tar,rewrite-timestamp=true"
  tar -xOf "$1/image.tar" index.json | jq -r '.manifests[0].digest'
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

# write_ref -> writes the tag in VERSION_FILE and the digest of a local build into RELEASE
write_ref() {
  local tag digest
  tag=$(image_tag)
  digest=$(build "$work/out")
  sed -E "s#reference: ${IMAGE_RE}:[0-9A-Za-z._-]+(@sha256:[0-9a-f]{64})?#reference: ${IMAGE}:${tag}@${digest}#" "$RELEASE" > "$work/release.yaml"
  cat "$work/release.yaml" > "$RELEASE"
  echo "Set ${IMAGE}:${tag}@${digest} in $RELEASE"
}

case "$MODE" in
  --tag)
    image_tag
    ;;
  --digest)
    release_ref | sed 's/.*@//'
    ;;
  --build)
    build "${2:?usage: $0 --build <dir>}"
    ;;
  --push)
    buildx "type=image,name=${2:?usage: $0 --push <ref>},push=true,rewrite-timestamp=true"
    ;;
  --check)
    want=$(image_tag)
    have=$(release_ref)
    if ! echo "$have" | grep -qE "^${IMAGE_RE}:${want//./\\.}@"; then
      echo "error: $RELEASE uses ${have}, but $VERSION_FILE is ${want}" >&2
      echo "Run 'task grafana:plugins' and commit the change." >&2
      exit 1
    fi
    echo "Grafana plugin image version ${want} is up to date"
    ;;
  --write-checksums)
    write_checksums
    ;;
  --write-ref)
    write_ref
    ;;
  "")
    write_checksums
    write_ref
    ;;
  *)
    echo "usage: $0 [--write-checksums|--write-ref|--check|--tag|--digest|--build <dir>|--push <ref>]" >&2
    exit 2
    ;;
esac
