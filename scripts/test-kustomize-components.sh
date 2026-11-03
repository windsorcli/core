#!/usr/bin/env bash
# Builds every case in each kustomize components.test.yaml with kubectl kustomize.
# Each case builds twice: in its listed order and sorted, as the composer sorts
# merged components. Every expect entry is a yq expression that MUST evaluate to
# true on each output document it selects.
set -euo pipefail

fail=0
found=0
work=$(mktemp -d)
plan=$(mktemp -d .components-test.XXXXXX)
trap 'rm -rf "$work" "$plan"' EXIT

build_case() {
  local base=$1 out=$2
  shift 2
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "components:"
    echo "- ../$base"
    for comp in "$@"; do
      echo "- ../$base/$comp"
    done
  } > "$plan/kustomization.yaml"
  kubectl kustomize "$plan" > "$out"
}

while IFS= read -r -d '' test_file; do
  found=$((found + 1))
  base=$(dirname "$test_file")
  echo "=== $test_file ==="
  count=$(yq '.cases | length' "$test_file")
  for ((i = 0; i < count; i++)); do
    name=$(yq ".cases[$i].name" "$test_file")
    listed=()
    while IFS= read -r comp; do listed+=("$comp"); done < <(yq ".cases[$i].components[]" "$test_file")
    sorted=()
    while IFS= read -r comp; do sorted+=("$comp"); done < <(printf '%s\n' "${listed[@]}" | LC_ALL=C sort)

    case_fail=0
    for order in listed sorted; do
      if [ "$order" = listed ]; then comps=("${listed[@]}"); else comps=("${sorted[@]}"); fi
      out="$work/out.yaml"
      if ! build_case "$base" "$out" "${comps[@]}" 2> "$work/err"; then
        echo "FAIL [$order] $name"
        cat "$work/err"
        case_fail=1
        continue
      fi
      expects=$(yq ".cases[$i].expect | length" "$test_file")
      for ((j = 0; j < expects; j++)); do
        expr=$(yq ".cases[$i].expect[$j]" "$test_file")
        result=$(yq ea "$expr" "$out" 2>&1 || true)
        if [ -z "$result" ] || grep -qv '^true$' <<< "$result"; then
          echo "FAIL [$order] $name: $expr"
          echo "  got: ${result:-<no matching document>}"
          case_fail=1
        fi
      done
    done
    if [ "$case_fail" -eq 0 ]; then echo "ok   $name"; else fail=1; fi
  done
done < <(find kustomize -name "components.test.yaml" -print0)

if [ "$found" -eq 0 ]; then
  echo "FAIL no components.test.yaml found under kustomize/"
  exit 1
fi

exit $fail
