#!/usr/bin/env bash
#
# terraform-module-index.sh - Materialize the BEGIN_TERRAFORM_MODULES /
# END_TERRAFORM_MODULES region of every terraform/<category>/README.md from
# the per-module READMEs nested under that category.
#
# Usage:
#   scripts/terraform-module-index.sh          # regen every category
#   scripts/terraform-module-index.sh --check  # CI: fail on drift
#
# A "category" is any terraform/<name>/README.md whose frontmatter declares
# stack_backing: — the same signal stack-index.sh uses to find layers for
# docs/index.md. Every README.md nested under it (any depth, excluding
# itself and vendored .terraform/ provider docs) is a module; the generated
# block links each one with the description from its own frontmatter.
#
# Every module README under a category must have a frontmatter
# `description:` field. Missing descriptions fail the script.

set -euo pipefail

BEGIN_MARKER='<!-- BEGIN_TERRAFORM_MODULES -->'
END_MARKER='<!-- END_TERRAFORM_MODULES -->'

# Extract frontmatter field $2 from file $1, print to stdout. Empty string
# if no frontmatter or no such field.
extract_frontmatter_field() {
  local file="$1" field="$2"
  awk -v field="$field" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && $0 ~ "^" field ":" {
      sub("^" field ": *", "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$file"
}

# Category root READMEs: terraform/<name>/README.md with a stack_backing:
# field. Categories are exactly one level below terraform/.
list_categories() {
  find terraform -mindepth 2 -maxdepth 2 -name README.md -type f | sort | while read -r readme; do
    if [ -n "$(extract_frontmatter_field "$readme" stack_backing)" ]; then
      dirname "$readme"
    fi
  done
}

# Module READMEs nested under category dir $1, any depth, excluding the
# category's own README.md and vendored provider docs.
list_modules() {
  local root="$1"
  find "$root" -mindepth 2 -name README.md -type f -not -path '*/.terraform/*' | sort
}

# Build the "## Modules" block for category $1 into stdout.
build_block() {
  local root="$1"
  local errors=0
  local readme rel desc

  printf '## Modules\n\n'

  while IFS= read -r readme; do
    [ -n "$readme" ] || continue
    rel="${readme#"$root"/}"
    rel="${rel%/README.md}"

    desc="$(extract_frontmatter_field "$readme" description)"
    if [ -z "$desc" ]; then
      echo "error: $readme has no frontmatter description:" >&2
      errors=1
      continue
    fi

    printf -- '- [%s](%s/) — %s\n' "$rel" "$rel" "$desc"
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

  if ! grep -qF "$BEGIN_MARKER" "$readme"; then
    echo "error: $readme missing $BEGIN_MARKER" >&2
    return 1
  fi
  if ! grep -qF "$END_MARKER" "$readme"; then
    echo "error: $readme missing $END_MARKER" >&2
    return 1
  fi

  local block
  block="$(mktemp)"
  if ! build_block "$root" > "$block"; then
    rm -f "$block"
    return 1
  fi
  inject "$readme" "$block"
  rm -f "$block"
  echo "ok: $readme" >&2
}

process_all() {
  local status=0
  while IFS= read -r category; do
    [ -n "$category" ] || continue
    process_one "$category" || status=1
  done < <(list_categories)
  return $status
}

usage() {
  cat >&2 <<'USAGE'
usage:
  terraform-module-index.sh          # regen every category README
  terraform-module-index.sh --check  # CI: fail on drift
USAGE
  exit 2
}

main() {
  # The terraform/ glob helpers below are relative to PWD. Without this
  # guard, a subdirectory invocation would silently find nothing and
  # --check would exit 0 while real drift sits untested.
  [[ -d terraform ]] || {
    echo "error: run terraform-module-index.sh from the repo root" >&2
    exit 1
  }

  case "${1:-}" in
    "")
      process_all
      ;;
    --check)
      process_all
      if ! git diff --exit-code -- 'terraform/*/README.md'; then
        echo "error: terraform-module-index produced drift. Run 'task docs:terraform' and commit the result." >&2
        exit 1
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
