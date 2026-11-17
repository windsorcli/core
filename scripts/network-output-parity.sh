#!/usr/bin/env bash
# Fails when a terraform/network/<module>-data module declares a different set of outputs than its <module> sibling.

set -euo pipefail

outputs() {
  sed -n 's/^output "\([^"]*\)".*/\1/p' "$1"/*.tf | sort -u
}

status=0
for data_dir in terraform/network/*-data; do
  [ -d "$data_dir" ] || continue
  create_dir="${data_dir%-data}"
  if [ ! -d "$create_dir" ]; then
    echo "error: $data_dir has no sibling $create_dir" >&2
    status=1
    continue
  fi
  if ! diff_out="$(diff <(outputs "$create_dir") <(outputs "$data_dir"))"; then
    echo "error: outputs differ between $create_dir (<) and $data_dir (>):" >&2
    echo "$diff_out" >&2
    status=1
  fi
done
exit "$status"
