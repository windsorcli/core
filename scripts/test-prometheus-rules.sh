#!/usr/bin/env bash
# Unit-tests every PrometheusRule via promtool. Finds each prometheus-rule.yaml
# with a sibling prometheus-rule.test.yaml, extracts .spec to a rule file
# promtool can load, and runs the test against it.
set -euo pipefail

fail=0

while IFS= read -r -d '' rule_file; do
  dir=$(dirname "$rule_file")
  test_file="$dir/prometheus-rule.test.yaml"
  [ -f "$test_file" ] || continue

  rendered="$dir/.rendered-rule.yml"
  yq '.spec' "$rule_file" > "$rendered"

  echo "=== $test_file ==="
  if ! promtool test rules "$test_file"; then
    fail=1
  fi
  rm -f "$rendered"
done < <(find kustomize -name "prometheus-rule.yaml" -print0)

exit $fail
