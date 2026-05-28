#!/usr/bin/env bash
#
# umbrella-index.sh - Materialize the BEGIN_INDEX / END_INDEX region of
# kustomize/README.md and terraform/README.md from per-module README
# frontmatter.
#
# Usage:
#   scripts/umbrella-index.sh                # regen both umbrellas
#   scripts/umbrella-index.sh --check        # CI: fail on drift
#
# Every per-module README (kustomize/*/README.md and terraform/**/README.md,
# excluding the umbrellas themselves and .terraform/) must have a frontmatter
# block with `description:` set. Missing descriptions fail the script.

set -euo pipefail

BEGIN_MARKER='<!-- BEGIN_INDEX -->'
END_MARKER='<!-- END_INDEX -->'

# Extract the description: field from $1's frontmatter, print to stdout.
# Empty string if no frontmatter or no description field.
extract_description() {
  local readme="$1"
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && /^description:/ {
      sub(/^description: */, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$readme"
}

# List per-module README paths under $1, excluding the umbrella itself.
# Kustomize add-ons are 1-level-deep (kustomize/<addon>/README.md); nested
# READMEs there are component-level notes, not add-ons. Terraform modules
# can be legitimately nested (cluster/talos/config, etc.), so allow any
# depth — but skip vendored provider READMEs under .terraform/.
list_modules() {
  local root="$1"
  if [ "$root" = "kustomize" ]; then
    find "$root" -maxdepth 2 -name README.md -type f \
      -not -path "$root/README.md" \
      | sort
  else
    find "$root" -name README.md -type f \
      -not -path "*/.terraform/*" \
      -not -path "$root/README.md" \
      | sort
  fi
}

# Build the index table for $1 (root subtree) into stdout.
build_table() {
  local root="$1"
  local errors=0
  # `readme` is the loop variable; declared local to keep it from leaking
  # into the caller (process_one also uses a `readme` variable).
  local readme rel desc

  printf '| Path | Purpose |\n'
  printf '|---|---|\n'

  while IFS= read -r readme; do
    rel="${readme#"$root"/}"
    rel="${rel%/README.md}"

    desc="$(extract_description "$readme")"
    if [ -z "$desc" ]; then
      echo "error: $readme has no frontmatter description:" >&2
      errors=1
      continue
    fi

    printf '| [%s](%s/) | %s |\n' "$rel" "$rel" "$desc"
  done < <(list_modules "$root")

  return $errors
}

# Replace the marker region in $readme with the content of $content_file.
inject() {
  local readme="$1"
  local content_file="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v cf="$content_file" '
    $0 == begin {
      print
      print ""
      while ((getline line < cf) > 0) print line
      close(cf)
      skip = 1
      next
    }
    $0 == end {
      print
      skip = 0
      next
    }
    !skip { print }
  ' "$readme" > "$tmp"

  mv "$tmp" "$readme"
}

process_one() {
  local root="$1"
  local readme="$root/README.md"

  if [ ! -f "$readme" ]; then
    echo "error: $readme missing" >&2
    return 1
  fi
  if ! grep -qF "$BEGIN_MARKER" "$readme"; then
    echo "error: $readme missing $BEGIN_MARKER" >&2
    return 1
  fi
  if ! grep -qF "$END_MARKER" "$readme"; then
    echo "error: $readme missing $END_MARKER" >&2
    return 1
  fi

  local table
  table="$(mktemp)"
  if ! build_table "$root" > "$table"; then
    rm -f "$table"
    return 1
  fi
  inject "$readme" "$table"
  rm -f "$table"
  echo "ok: $readme" >&2
}

usage() {
  cat >&2 <<'USAGE'
usage:
  umbrella-index.sh <root>            # regen <root>/README.md (root = kustomize|terraform)
  umbrella-index.sh --check <root>    # CI: fail on drift in <root>/README.md
USAGE
  exit 2
}

main() {
  local check=0 root=""
  case "${1:-}" in
    --check) check=1; root="${2:-}" ;;
    -h|--help) usage ;;
    "") usage ;;
    *) root="$1" ;;
  esac

  [[ "$root" == "kustomize" || "$root" == "terraform" ]] || {
    echo "error: root must be 'kustomize' or 'terraform' (got '$root')" >&2
    usage
  }

  # Index roots are repo-relative; without this guard, --check would
  # silently pass when run from anywhere else.
  [[ -d "$root" ]] || {
    echo "error: run umbrella-index.sh from the repo root" >&2
    exit 1
  }

  process_one "$root"

  if [ "$check" -eq 1 ]; then
    if ! git diff --exit-code -- "$root/README.md"; then
      echo "error: $root/README.md has drift. Run 'task docs:$root' and commit the result." >&2
      exit 1
    fi
  fi
}

main "$@"
