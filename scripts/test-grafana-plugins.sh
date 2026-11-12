#!/usr/bin/env bash
# Tests scripts/grafana-plugins.sh on a copy of the image directory and the grafana/quickwit
# patch. Checks that the Grafana HelmRelease turns off each plugin download, and that only
# grafana/quickwit mounts the plugin image.
# The chart renders an extraVolumes entry as an emptyDir, so the image volume MUST be in extraContainerVolumes.
set -euo pipefail

BASE="kustomize/observability/install/grafana/helm-release.yaml"
RELEASE="kustomize/observability/install/grafana/quickwit/patches/helm-release.yaml"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

# check <name> <command...> -> runs the command in the copy and records a failure
check() {
  local name="$1"
  shift
  if (cd "$work" && "$@" >/dev/null 2>&1); then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    fail=1
  fi
}

mkdir -p "$work/scripts" "$work/images" "$(dirname "$work/$RELEASE")"
cp scripts/grafana-plugins.sh "$work/scripts/"
cp -R images/grafana-plugins "$work/images/"
cp "$RELEASE" "$work/$RELEASE"

check "the committed tag matches the image content" scripts/grafana-plugins.sh --check

echo "# test" >> "$work/images/grafana-plugins/Dockerfile"
check "a change to the image fails the check" sh -c '! scripts/grafana-plugins.sh --check'
check "the script writes the new tag" scripts/grafana-plugins.sh
check "the check passes after the script writes the tag" scripts/grafana-plugins.sh --check
check "the image line keeps its artifact tag" \
  grep -qE "reference: ghcr.io/windsorcli/grafana-plugins:[0-9a-f]{12}  # artifact: type=image$" "$RELEASE"

# expect <file> <path>=<value> ... -> records a failure for each path whose value in file differs
expect() {
  local file="$1" setting path want have
  shift
  for setting in "$@"; do
    path="${setting%=*}"
    want="${setting##*=}"
    have=$(yq -o json "$path" "$file" | tr -d ' \n')
    if [ "$have" = "$want" ]; then
      echo "ok: $file $path is $want"
    else
      echo "FAIL: $file $path is '$have', want '$want'"
      fail=1
    fi
  done
}

expect "$BASE" \
  '.spec.values."grafana.ini".plugins.preinstall_disabled=true' \
  '.spec.values."grafana.ini".plugins.public_key_retrieval_disabled=true' \
  '.spec.values."grafana.ini".analytics.reporting_enabled=false' \
  '.spec.values."grafana.ini".analytics.check_for_updates=false' \
  '.spec.values."grafana.ini".analytics.check_for_plugin_updates=false' \
  '.spec.values.plugins=[]' \
  '.spec.values.extraContainerVolumes=null' \
  '.spec.values.extraVolumeMounts=null'
expect "$RELEASE" \
  '[.spec.values.extraContainerVolumes[] | select(.name == "plugins") | .image.reference | test("^ghcr.io/windsorcli/grafana-plugins:")]=[true]' \
  '[.spec.values.extraVolumes[]? | select(.name == "plugins")] | length=0'

fetched=$(grep -oE '^ *fetch [a-z0-9-]+ ' images/grafana-plugins/Dockerfile | awk '{print $2}')
mounts=$(yq '.spec.values.extraVolumeMounts[] | select(.name == "plugins") | .subPath' "$RELEASE")
for sub in $mounts; do
  if echo "$fetched" | grep -qx "$sub"; then
    echo "ok: the image holds the mounted plugin $sub"
  else
    echo "FAIL: a mount uses subPath $sub, but the image does not fetch it"
    fail=1
  fi
done
for id in $fetched; do
  if echo "$mounts" | grep -qx "$id"; then
    echo "ok: a mount uses the image plugin $id"
  else
    echo "FAIL: the image fetches $id, but no mount uses it"
    fail=1
  fi
done

if grep -rq "extraInitContainers" kustomize/observability/install/grafana; then
  echo "FAIL: a Grafana patch adds an init container"
  fail=1
else
  echo "ok: Grafana has no init container"
fi

exit $fail
