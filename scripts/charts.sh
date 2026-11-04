#!/usr/bin/env bash
# Fail when a Helm chart source breaks the charts.registry layout or flux-mirror.yaml misses a chart.
#
# A chart lives in charts.registry at <registry>/<chart name>:<chart version>. A base OCIRepository
# carries `${chart_registry:=<upstream base>}/<chart>`. An HTTP chart's HelmRelease carries a sibling
# chart-registry/ component whose OCIRepository carries `${chart_registry}/<chart>`. flux-mirror.yaml MUST
# list every chart and version the manifests and Terraform stacks pin, and nothing else.

set -euo pipefail

KUSTOMIZE_DIR="kustomize"
MIRROR_CONFIG="flux-mirror.yaml"

errors=0
fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

# Rows of: chart<TAB>version<TAB>upstream. upstream is an oci:// chart reference, or an HTTP
# repository URL followed by a space and the chart name.
rows=()

# OCI-published charts: the base OCIRepository names both the upstream and the chart.
while IFS= read -r file; do
  url=$(yq 'select(.kind == "OCIRepository") | .spec.url' "$file")
  tag=$(yq 'select(.kind == "OCIRepository") | .spec.ref.tag' "$file")
  if [[ "$url" =~ ^\$\{chart_registry:=(oci://[^}]+)\}/([^/]+)$ ]]; then
    rows+=("${BASH_REMATCH[2]}	$tag	${BASH_REMATCH[1]}/${BASH_REMATCH[2]}")
  else
    fail "$file: url must be \${chart_registry:=<upstream base>}/<chart>, got $url"
  fi
done < <(find "$KUSTOMIZE_DIR" -name oci-repository.yaml -not -path '*/chart-registry/*' | sort)

# HTTP-published charts: each HelmRelease on a HelmRepository needs a matching chart-registry/ component.
build_dir=$(mktemp -d "$KUSTOMIZE_DIR/.charts-check.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
while IFS= read -r file; do
  while IFS=$'\t' read -r name ns chart version repo; do
    [ -n "$name" ] || continue
    upstream_url=$(find "$KUSTOMIZE_DIR" -name helm-repository.yaml -exec yq \
      "select(.kind == \"HelmRepository\" and .metadata.name == \"$repo\" and .metadata.namespace == \"$ns\") | .spec.url" {} \; |
      head -n1)
    [ -n "$upstream_url" ] || fail "$file: HelmRepository $ns/$repo not found"
    oci="$(dirname "$file")/chart-registry/oci-repository.yaml"
    if [ ! -f "$oci" ]; then
      fail "$file: HelmRelease $ns/$name has no chart-registry/oci-repository.yaml"
      continue
    fi
    [ "$repo" = "$name" ] || fail "$file: HelmRelease $ns/$name uses HelmRepository $repo; name the HelmRepository after the release"
    # shellcheck disable=SC2016
    deleted=$(yq -r '.patches[].patch | select(test("^\$patch: delete")) | from_yaml | select(.kind == "HelmRepository") | .metadata.name' \
      "$(dirname "$oci")/kustomization.yaml")
    [ "$deleted" = "$repo" ] || fail "$(dirname "$oci")/kustomization.yaml: must delete HelmRepository $repo, deletes ${deleted:-nothing}"
    base="${file#"$KUSTOMIZE_DIR"/}"
    base="${base%/*}"
    printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\ncomponents:\n  - ../%s\n  - ../%s/chart-registry\n' \
      "$base" "$base" >"$build_dir/kustomization.yaml"
    build_err=$(kustomize build "$build_dir" 2>&1 >/dev/null) ||
      fail "$base/chart-registry: kustomize build with its base fails: ${build_err%%$'\n'*}"
    oci_name=$(yq 'select(.kind == "OCIRepository") | .metadata.name' "$oci")
    url=$(yq 'select(.kind == "OCIRepository") | .spec.url' "$oci")
    tag=$(yq 'select(.kind == "OCIRepository") | .spec.ref.tag' "$oci")
    [ "$oci_name" = "$name" ] || fail "$oci: OCIRepository is $oci_name, HelmRelease is $name"
    [ "$tag" = "$version" ] || fail "$oci: tag $tag does not match HelmRelease version $version"
    [ "$url" = "\${chart_registry}/$chart" ] || fail "$oci: url must be \${chart_registry}/$chart, got $url"
    rows+=("$chart	$tag	${upstream_url%/} $chart")
  done < <(yq -r 'select(.kind == "HelmRelease" and .spec.chart.spec.sourceRef.kind == "HelmRepository") |
    [.metadata.name, .metadata.namespace, .spec.chart.spec.chart, .spec.chart.spec.version, .spec.chart.spec.sourceRef.name] | @tsv' "$file")
done < <(grep -rl --include='*.yaml' 'kind: HelmRelease' "$KUSTOMIZE_DIR" | sort)

# Terraform-installed charts: chart_repository plus the chart's version variable, read from defaults.
tf_default() {
  awk -v v="variable \"$2\"" '$0 ~ v {f=1} f && /default *=/ {gsub(/.*= *"|".*/, ""); print; exit}' "$1"
}
for entry in "cni/cilium cilium cilium_version" \
  "gitops/flux flux-operator flux_operator_version" \
  "gitops/flux flux-instance flux_operator_version"; do
  read -r stack chart version_var <<<"$entry"
  vars="terraform/$stack/variables.tf"
  base=$(tf_default "$vars" chart_repository)
  version=$(tf_default "$vars" "$version_var")
  if [[ "$base" == oci://* && -n "$version" ]]; then
    rows+=("$chart	$version	${base%/}/$chart")
  else
    fail "$vars: expected an oci:// chart_repository default and a $version_var default"
  fi
done

# shellcheck disable=SC2016
while IFS= read -r file; do
  [ "$(yq 'select(.kind == "OCIRepository") | .spec.insecure' "$file")" = '${chart_registry_insecure:=false}' ] ||
    fail "$file: spec.insecure must be \${chart_registry_insecure:=false}"
done < <(find "$KUSTOMIZE_DIR" -name oci-repository.yaml | sort)

while IFS= read -r file; do
  fail "$file: HelmRepository type oci; use an OCIRepository"
done < <(grep -rl --include='*.yaml' -E '^\s+type: oci\s*$' "$KUSTOMIZE_DIR" || true)

# helm push names the reference after the chart, so two upstream charts MUST NOT share a name.
while IFS= read -r dup; do
  fail "chart name $dup comes from more than one upstream"
done < <(printf '%s\n' "${rows[@]}" | awk -F'\t' '{print $1 "\t" $3}' | sort -u | cut -f1 | uniq -d)

# flux-mirror.yaml entries, in the same row format.
mirror_rows=()
while IFS=$'\t' read -r name version source destination; do
  [ "$destination" = "oci://\${CHART_REGISTRY}" ] || fail "$MIRROR_CONFIG: chart $name destination must be oci://\${CHART_REGISTRY}"
  mirror_rows+=("$name	$version	${source%/} $name")
done < <(yq -r '.charts[] | [.name, .version, .source, .destination] | @tsv' "$MIRROR_CONFIG")
while IFS=$'\t' read -r source version pattern destination; do
  chart="${source##*/}"
  [ "$destination" = "\${CHART_REGISTRY}/$chart" ] || fail "$MIRROR_CONFIG: $source destination must be \${CHART_REGISTRY}/$chart"
  if [[ "$version" == v* ]]; then want='^v'; else want='^[0-9]'; fi
  [ "$pattern" = "$want" ] || fail "$MIRROR_CONFIG: $source selector.regex.pattern must be '$want' for tag $version"
  mirror_rows+=("$chart	$version	oci://$source")
done < <(yq -r '.artifacts[] | [.source, .selector.semver, .selector.regex.pattern, .destination] | @tsv' "$MIRROR_CONFIG")

while IFS= read -r line; do
  case "$line" in
    "< "*) fail "$MIRROR_CONFIG: missing ${line#< }" ;;
    "> "*) fail "$MIRROR_CONFIG: not pinned by any chart source: ${line#> }" ;;
  esac
done < <(diff <(printf '%s\n' "${rows[@]}" | sort -u) <(printf '%s\n' "${mirror_rows[@]}" | sort -u) || true)

if [ "$errors" -gt 0 ]; then
  echo "$errors chart source error(s)" >&2
  exit 1
fi
