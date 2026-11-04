#!/usr/bin/env bash
# Copy every chart in flux-mirror.yaml into a local registry and pull each one back by name and version.

set -euo pipefail

MIRROR_CONFIG="flux-mirror.yaml"
PORT="${CHARTS_TEST_PORT:-5050}"
REGISTRY="localhost:$PORT/windsor"
CONTAINER="windsor-charts-test"

errors=0
fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

work_dir=$(mktemp -d)
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" -p "127.0.0.1:$PORT:5000" registry:3 >/dev/null
for _ in $(seq 1 30); do
  curl -fs "http://localhost:$PORT/v2/" >/dev/null && break
  sleep 1
done

CHART_REGISTRY="$REGISTRY" flux mirror sync "$MIRROR_CONFIG" "$@"

# Rows of: chart<TAB>version, from both entry kinds.
rows=$(
  yq -r '.charts[] | [.name, .version] | @tsv' "$MIRROR_CONFIG"
  yq -r '.artifacts[] | [(.source | split("/") | .[-1]), .selector.semver] | @tsv' "$MIRROR_CONFIG"
)

while IFS=$'\t' read -r chart version; do
  ref="oci://$REGISTRY/$chart"
  if ! meta=$(helm show chart "$ref" --version "$version" --plain-http 2>"$work_dir/err"); then
    fail "$ref:$version does not pull: $(head -n1 "$work_dir/err")"
    continue
  fi
  name=$(yq '.name' <<<"$meta")
  chart_version=$(yq '.version' <<<"$meta")
  [ "$name" = "$chart" ] || fail "$ref:$version: Chart.yaml name is $name"
  [ "$chart_version" = "$version" ] || fail "$ref:$version: Chart.yaml version is $chart_version"
  echo "ok $chart $version"
done <<<"$rows"

if [ "$errors" -gt 0 ]; then
  echo "$errors chart(s) failed" >&2
  exit 1
fi
