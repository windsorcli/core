#!/usr/bin/env bash
# Vendor dashboards from upstream sources and validate patches
# Usage: scripts/vendor-dashboards.sh

set -euo pipefail

ERROR_FILE=$(mktemp)
echo 0 > "$ERROR_FILE"
trap 'rm -f "$ERROR_FILE"' EXIT

# Find all source.yaml files
find . -name 'source.yaml' -type f | while read -r source_file; do
  vendor_dir="$(dirname "$source_file")/"
  
  echo "Processing ${vendor_dir#./}..."
  
  # Parse upstream base URL
  base_url=$(grep '^[[:space:]]*url:' "$source_file" | head -1 | awk '{print $2}')
  [ -n "$base_url" ] && echo "  Upstream: $base_url"
  
  # Parse files and process each
  export base_url vendor_dir ERROR_FILE
  awk 'BEGIN { OFS="|" }
    /^[[:space:]]+-[[:space:]]+name:/ { 
      if (name) print name, (url ? url : "-"), (patch ? patch : "-")
      name=$NF; url=""; patch=""
    }
    /^[[:space:]]+url:/ { url=$2 }
    /^[[:space:]]+patch:/ { patch=$2 }
    END { if (name) print name, (url ? url : "-"), (patch ? patch : "-") }
  ' "$source_file" | while IFS='|' read -r file url patch; do
    [ "$url" = "-" ] && url=""
    [ "$patch" = "-" ] && patch=""
    [ -z "$file" ] && continue
    output="${vendor_dir}${file}"
    
    # Vendor: fetch and patch
    # Use explicit URL or construct from base
    if [ -n "$url" ]; then
      fetch_url="$url"
    elif [ -n "$base_url" ]; then
      fetch_url="${base_url}/${file}"
    else
      echo "  ERROR: No URL for $file"
      continue
    fi
    
    echo "  Fetching $file..."
    upstream=$(curl -sL "$fetch_url")
    
    if [ -n "$patch" ]; then
      if [ ! -f "${vendor_dir}${patch}" ]; then
        echo "  ERROR: Patch file not found: ${patch}"
        echo $(( $(cat "$ERROR_FILE") + 1 )) > "$ERROR_FILE"
        continue
      fi
      echo "  Applying ${patch}..."
      echo "$upstream" | jq --argjson ops "$(cat "${vendor_dir}${patch}")" '
        reduce $ops[] as $op (.;
          ($op.path | split("/") | .[1:] | map(if test("^[0-9]+$") then tonumber else . end)) as $path |
          if $op.op == "replace" then setpath($path; $op.value)
          elif $op.op == "add" then setpath($path; $op.value)
          elif $op.op == "remove" then delpaths([$path])
          else error("Unsupported patch operation: \($op.op) at path \($op.path)")
          end
        )
      ' > "$output"
      
      # Validate JSON
      if ! jq empty "$output" 2>/dev/null; then
        echo "  ERROR: Patch produced invalid JSON"
        echo $(( $(cat "$ERROR_FILE") + 1 )) > "$ERROR_FILE"
        continue
      fi
    else
      echo "$upstream" > "$output"
    fi
    
    # Escape Grafana variables to prevent Flux substitution
    sed -i '' 's/\${\([^}]*\)}/$\${\1}/g' "$output" 2>/dev/null || \
    sed -i 's/\${\([^}]*\)}/$\${\1}/g' "$output"
    
    # Validate JSON
    if ! jq empty "$output" 2>/dev/null; then
      echo "  ERROR: Invalid JSON in $file"
      echo $(( $(cat "$ERROR_FILE") + 1 )) > "$ERROR_FILE"
      continue
    fi
    echo "  ✓ $file: valid JSON"
    
    # Validate patch file if exists
    if [ -n "$patch" ] && [ -f "${vendor_dir}${patch}" ]; then
      if ! jq -e 'type == "array"' "${vendor_dir}${patch}" >/dev/null 2>&1; then
        echo "  ERROR: Invalid patch file: $patch"
        echo $(( $(cat "$ERROR_FILE") + 1 )) > "$ERROR_FILE"
      else
        ops=$(jq 'length' "${vendor_dir}${patch}")
        echo "  ✓ $patch: $ops operations"
      fi
    fi
  done
done

ERRORS=$(cat "$ERROR_FILE")

if [ "$ERRORS" -gt 0 ]; then
  echo "Validation failed with $ERRORS error(s)"
  exit 1
fi

echo "Done."
