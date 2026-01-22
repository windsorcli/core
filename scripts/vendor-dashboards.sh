#!/usr/bin/env bash
# Vendor dashboards from upstream sources defined in source.yaml files
# Usage: scripts/vendor-dashboards.sh

set -euo pipefail

# Find all source.yaml files in the repo
find . -name 'source.yaml' -type f | while read -r source_file; do
  vendor_dir="$(dirname "$source_file")/"
  
  echo "Processing ${vendor_dir#./}..."
  
  # Parse upstream base URL
  base_url=$(grep '^[[:space:]]*url:' "$source_file" | head -1 | awk '{print $2}')
  [ -n "$base_url" ] && echo "  Upstream: $base_url"
  
  # Parse files and process each (export base_url for subshell)
  export base_url vendor_dir
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
        exit 1
      fi
      echo "  Applying ${patch}..."
      echo "$upstream" | jq --argjson ops "$(cat "${vendor_dir}${patch}")" '
        reduce $ops[] as $op (.;
          ($op.path | split("/") | .[1:] | map(if test("^[0-9]+$") then tonumber else . end)) as $path |
          if $op.op == "replace" then setpath($path; $op.value)
          elif $op.op == "add" then setpath($path; $op.value)
          elif $op.op == "remove" then delpaths([$path])
          else .
          end
        )
      ' > "$output"
    else
      echo "$upstream" > "$output"
    fi
    
    # Escape Grafana variables to prevent Flux substitution
    # $${var} becomes ${var} after Flux processing
    sed -i '' 's/\${\([^}]*\)}/$\${\1}/g' "$output" 2>/dev/null || \
    sed -i 's/\${\([^}]*\)}/$\${\1}/g' "$output"
  done
done

echo "Done."
