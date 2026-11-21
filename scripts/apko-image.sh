#!/usr/bin/env bash
# Locks the packages in images/<name>, then sets VERSION and the tag and digest in each kustomize/ and terraform/ reference.
# A wrapper per image sets IMAGE_NAME and VERSION_PACKAGE, the package whose upstream version the tag follows.
#
#   <wrapper>             lock the packages, then write the tag and digest
#   <wrapper> --write-ref write only VERSION, the tag and the digest (no lock)
#   <wrapper> --check     verify each reference uses VERSION; non-zero on drift (CI)
#   <wrapper> --tag       print the version
#   <wrapper> --digest    print the digest that the references pin
#   <wrapper> --build <dir> build <dir>/image.tar and <dir>/sbom, and print the digest
#   <wrapper> --push <ref>  build and push the image to <ref>

set -euo pipefail

NAME="${IMAGE_NAME:?IMAGE_NAME MUST name a directory under images/}"
PACKAGE_RE="${VERSION_PACKAGE:?VERSION_PACKAGE MUST match the package that the tag follows}"
IMAGE_DIR="images/$NAME"
CONFIG="$IMAGE_DIR/apko.yaml"
LOCK="$IMAGE_DIR/apko.lock.json"
VERSION_FILE="$IMAGE_DIR/VERSION"
IMAGE="ghcr.io/windsorcli/$NAME"
IMAGE_RE="ghcr\\.io/windsorcli/${NAME//./\\.}"
REF_RE="${IMAGE_RE}:[0-9A-Za-z._-]+@sha256:[0-9a-f]{64}"
SEARCH_DIRS="kustomize terraform"
MODE="${1:-}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# package_version -> the upstream version of PACKAGE_RE in LOCK, or an error when the lock has none or several
package_version() {
  local versions
  versions=$(jq -r --arg re "$PACKAGE_RE" '[.contents.packages[] | select(.name | test($re)) | .version | sub("-r[0-9]+$"; "")] | unique | .[]' "$LOCK")
  if [ -z "$versions" ] || [ "$(echo "$versions" | wc -l)" -ne 1 ]; then
    echo "error: $LOCK MUST lock exactly one version of $PACKAGE_RE, not '${versions}'" >&2
    exit 1
  fi
  echo "$versions"
}

# image_tag -> the tag in VERSION_FILE, which MUST be <upstream version>-r<revision>
image_tag() {
  local version upstream
  version=$(tr -d '[:space:]' < "$VERSION_FILE")
  upstream=$(package_version)
  if ! echo "$version" | grep -qxE "${upstream//./\\.}-r[0-9]+"; then
    echo "error: $VERSION_FILE MUST hold ${upstream}-r<revision> to match $PACKAGE_RE in $LOCK, not '$version'" >&2
    exit 1
  fi
  echo "$version"
}

# ref_files -> each file under SEARCH_DIRS that references IMAGE, or an error when none does
ref_files() {
  local files
  # shellcheck disable=SC2086
  files=$(grep -rlE "$IMAGE_RE" $SEARCH_DIRS | LC_ALL=C sort) || true
  if [ -z "$files" ]; then
    echo "error: no file under $SEARCH_DIRS references $IMAGE" >&2
    exit 1
  fi
  echo "$files"
}

# refs -> each distinct reference to IMAGE, or an error when one has no tag and digest
refs() {
  local files bad
  files=$(ref_files)
  # shellcheck disable=SC2086
  bad=$(grep -hoE "${IMAGE_RE}[^[:space:]\"']*" $files | grep -vxE "$REF_RE" | grep -vxE "$IMAGE_RE" || true)
  if [ -n "$bad" ]; then
    echo "error: each reference MUST have the form ${IMAGE}:<tag>@sha256:<digest>: $bad" >&2
    exit 1
  fi
  # shellcheck disable=SC2086
  grep -hoE "$REF_RE" $files | LC_ALL=C sort -u
}

# pinned_digest -> the digest that every reference pins, or an error when they differ
pinned_digest() {
  local digests
  digests=$(refs | sed 's/.*@//' | LC_ALL=C sort -u)
  if [ "$(echo "$digests" | wc -l)" -ne 1 ]; then
    echo "error: the references to $IMAGE pin more than one digest:" >&2
    echo "$digests" >&2
    exit 1
  fi
  echo "$digests"
}

# build <dir> -> builds <dir>/image.tar and an SPDX SBOM for the index and each arch into <dir>/sbom, and prints the index digest
build() {
  local arch
  mkdir -p "$1/sbom"
  apko build --vcs=false --sbom-path "$1/sbom" --lockfile "$LOCK" "$CONFIG" "$IMAGE:build" "$1/image.tar" >"$work/build.log" 2>&1 || {
    cat "$work/build.log" >&2
    exit 1
  }
  for arch in index amd64:x86_64 arm64:aarch64; do
    mv "$1/sbom/sbom-${arch#*:}.spdx.json" "$1/sbom/${arch%%:*}.spdx.json"
  done
  echo "sha256:$(tar -xOf "$1/image.tar" index.json | sha256sum | cut -d' ' -f1)"
}

# next_version -> the next revision when the build differs from the pin and VERSION_FILE matches origin/main, else VERSION_FILE
next_version() {
  local digest="$1" version upstream released
  version=$(tr -d '[:space:]' < "$VERSION_FILE")
  upstream=$(package_version)
  released=$(git show "origin/main:$VERSION_FILE" 2>/dev/null | tr -d '[:space:]') || true
  if ! echo "$version" | grep -qxE "${upstream//./\\.}-r[0-9]+"; then
    echo "${upstream}-r1"
  elif [ "$digest" != "$(pinned_digest)" ] && [ "$version" = "$released" ]; then
    echo "${upstream}-r$(( ${version##*-r} + 1 ))"
  else
    echo "$version"
  fi
}

# write_ref -> writes VERSION_FILE and the tag and digest for the current content of IMAGE_DIR into each reference
write_ref() {
  local tag digest file
  digest=$(build "$work/out")
  next_version "$digest" > "$work/version"
  cat "$work/version" > "$VERSION_FILE"
  tag=$(image_tag)
  for file in $(ref_files); do
    sed -E "s#${REF_RE}#${IMAGE}:${tag}@${digest}#g" "$file" > "$work/file"
    cat "$work/file" > "$file"
  done
  echo "Set ${IMAGE}:${tag}@${digest}"
}

case "$MODE" in
  --tag)
    image_tag
    ;;
  --digest)
    pinned_digest
    ;;
  --build)
    build "${2:?usage: $0 --build <dir>}"
    ;;
  --push)
    apko publish --vcs=false --sbom=false --lockfile "$LOCK" "$CONFIG" "${2:?usage: $0 --push <ref>}" >"$work/push.log" 2>&1 || {
      cat "$work/push.log" >&2
      exit 1
    }
    ;;
  --check)
    want=$(image_tag)
    stale=$(refs | grep -vE "^${IMAGE_RE}:${want}@" || true)
    pinned_digest >/dev/null
    if [ -n "$stale" ]; then
      echo "error: $VERSION_FILE is ${want}, but these references differ:" >&2
      echo "$stale" >&2
      echo "Run 'task ${NAME}:image' and commit the change." >&2
      exit 1
    fi
    echo "${NAME} image version ${want} is up to date"
    ;;
  --write-ref)
    write_ref
    ;;
  "")
    apko lock "$CONFIG" --output "$LOCK"
    write_ref
    ;;
  *)
    echo "usage: $0 [--write-ref|--check|--tag|--digest|--build <dir>|--push <ref>]" >&2
    exit 2
    ;;
esac
