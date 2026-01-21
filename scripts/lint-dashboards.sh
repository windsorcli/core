#!/usr/bin/env bash
# Validate vendored JSON files and patch integrity
# Usage: scripts/lint-dashboards.sh

set -euo pipefail

ERROR_FILE=$(mktemp)
echo 0 > "$ERROR_FILE"
trap 'rm -f "$ERROR_FILE"' EXIT

# Find all source.yaml files in the repo
find . -name 'source.yaml' -type f | while read source_file; do
  vendor_dir="$(dirname "$source_file")/"
  
  echo "Validating ${vendor_dir#./}..."
  
  # Check all JSON files are valid
  for json_file in "$vendor_dir"*.json; do
    [ -f "$json_file" ] || continue
    filename=$(basename "$json_file")
    jq_err=$(jq . "$json_file" 2>&1 >/dev/null)
    if [ -n "$jq_err" ]; then
      echo "  ERROR: Invalid JSON in $filename"
      echo $(( $(cat "$ERROR_FILE") + 1 )) > "$ERROR_FILE"
    else
      echo "  ✓ $filename: valid JSON"
    fi
  done
  
  # Check all patch files are valid JSON arrays
  for patch_file in "$vendor_dir"patches/*.patch.json; do
    [ -f "$patch_file" ] || continue
    filename=$(basename "$patch_file")
    if ! jq -e 'type == "array"' "$patch_file" >/dev/null 2>&1; then
      echo "  ERROR: Patch must be JSON array: $filename"
      echo $(( $(cat "$ERROR_FILE") + 1 )) > "$ERROR_FILE"
    else
      ops=$(jq 'length' "$patch_file")
      echo "  ✓ $filename: $ops operations"
    fi
  done
done

ERRORS=$(cat "$ERROR_FILE")

if [ "$ERRORS" -gt 0 ]; then
  echo "Validation failed with $ERRORS errors"
  exit 1
fi

echo "All dashboards validated successfully"
