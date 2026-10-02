#!/usr/bin/env bash
# Unit-tests each Composition's or WatchOperation's embedded Python function
# via its sibling *.test.py. Extracts the pipeline script to a real .py file
# so the test can import it as a module.
set -euo pipefail

fail=0

while IFS= read -r -d '' comp_file; do
  dir=$(dirname "$comp_file")
  test_file="$dir/composition.test.py"
  [ -f "$test_file" ] || continue

  rendered="$dir/.rendered-composition.py"
  yq -r '.spec.pipeline[0].input.script' "$comp_file" > "$rendered"

  echo "=== $test_file ==="
  if ! COMPOSITION_SCRIPT="$rendered" python3 "$test_file"; then
    fail=1
  fi
  rm -f "$rendered"
done < <(find kustomize -name "composition.yaml" -print0)

while IFS= read -r -d '' watch_file; do
  dir=$(dirname "$watch_file")
  test_file="$dir/watch-operation.test.py"
  [ -f "$test_file" ] || continue

  rendered="$dir/.rendered-watch-operation.py"
  yq -r '.spec.operationTemplate.spec.pipeline[0].input.script' "$watch_file" > "$rendered"

  echo "=== $test_file ==="
  if ! COMPOSITION_SCRIPT="$rendered" python3 "$test_file"; then
    fail=1
  fi
  rm -f "$rendered"
done < <(find kustomize -name "watch-operation.yaml" -print0)

exit $fail
