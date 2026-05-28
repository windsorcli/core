#!/usr/bin/env bash
#
# kustomize-docs.sh - Materialize the BEGIN_KUSTOMIZE_DOCS / END_KUSTOMIZE_DOCS
# region of kustomize/<add-on>/README.md from kustomize/<add-on>/.docs.yaml.
#
# Usage:
#   scripts/kustomize-docs.sh kustomize/<add-on>     # one add-on
#   scripts/kustomize-docs.sh --all                  # every add-on with .docs.yaml
#   scripts/kustomize-docs.sh --check                # CI: fail on drift
#
# Requires: yq v4 (mikefarah). Available via aqua.

set -euo pipefail

BEGIN_MARKER='<!-- BEGIN_KUSTOMIZE_DOCS -->'
END_MARKER='<!-- END_KUSTOMIZE_DOCS -->'

# Render Substitutions / Components / Dependencies tables to stdout.
render_tables() {
  local docs="$1"

  # yq expressions are intentionally single-quoted: their `.field` syntax
  # must reach yq verbatim, not be expanded by the shell.
  if yq -e '.substitutions' "$docs" >/dev/null 2>&1; then
    printf '## Substitutions\n\n'
    printf '| Name | Required when | Effect |\n'
    printf '|---|---|---|\n'
    # shellcheck disable=SC2016
    yq -r '
      .substitutions | to_entries[] |
      "| `" + .key + "` | " +
      (.value.required_when // "always") + " | " +
      (.value.description // "") + " |"
    ' "$docs"
    printf '\n'
  fi

  if yq -e '.components' "$docs" >/dev/null 2>&1; then
    if yq -e '.facets' "$docs" >/dev/null 2>&1; then
      # Multi-facet add-on (e.g. base/resources split). Validate that every
      # component declares a `facet:` matching one in `.facets[]`, then
      # render one Components sub-table per facet in declared order.
      local facets_file errors=0
      facets_file="$(mktemp)"
      yq -r '.facets[]' "$docs" > "$facets_file"
      while IFS=$'\t' read -r component facet; do
        if [ -z "$facet" ]; then
          echo "error: $docs: component '$component' has no .facet field" >&2
          errors=1
        elif ! grep -qFx -- "$facet" "$facets_file"; then
          echo "error: $docs: component '$component' references unknown facet '$facet'" >&2
          errors=1
        fi
      done < <(yq -r '.components | to_entries[] | .key + "\t" + (.value.facet // "")' "$docs")
      if [ "$errors" -ne 0 ]; then
        rm -f "$facets_file"
        return 1
      fi
      while IFS= read -r facet; do
        # Literal backticks render markdown code spans; SC2016's "single-
        # quoted expression won't expand" is a false positive here.
        # shellcheck disable=SC2016
        printf '## Components — `%s`\n\n' "$facet"
        printf '| Component | Enable when | Effect |\n'
        printf '|---|---|---|\n'
        # shellcheck disable=SC2016
        FACET="$facet" yq -r '
          .components | to_entries[] |
          select(.value.facet == strenv(FACET)) |
          "| `" + .key + "` | " +
          (.value.enable_when // "always") + " | " +
          (.value.description // "") + " |"
        ' "$docs"
        printf '\n'
      done < "$facets_file"
      rm -f "$facets_file"
    else
      printf '## Components\n\n'
      printf '| Component | Enable when | Effect |\n'
      printf '|---|---|---|\n'
      # shellcheck disable=SC2016
      yq -r '
        .components | to_entries[] |
        "| `" + .key + "` | " +
        (.value.enable_when // "always") + " | " +
        (.value.description // "") + " |"
      ' "$docs"
      printf '\n'
    fi
  fi

  if yq -e '.dependencies' "$docs" >/dev/null 2>&1; then
    printf '## Dependencies\n\n'
    printf '| Add-on | Required when | Reason |\n'
    printf '|---|---|---|\n'
    # shellcheck disable=SC2016
    yq -r '
      .dependencies | to_entries[] |
      "| `" + .key + "` | " +
      (.value.required_when // "always") + " | " +
      (.value.reason // "") + " |"
    ' "$docs"
    printf '\n'
  fi
}

# Replace the marker region in $readme with the contents of $rendered_file.
# Passing multi-line content via -v doesn't work in awk; use getline from a
# temp file instead.
inject() {
  local readme="$1"
  local rendered_file="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v rf="$rendered_file" '
    $0 == begin {
      print
      print ""
      while ((getline line < rf) > 0) print line
      close(rf)
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

process_dir() {
  local dir="${1%/}"
  local readme="$dir/README.md"
  local docs="$dir/.docs.yaml"

  if [ ! -f "$docs" ]; then
    echo "skip: $dir (no .docs.yaml)" >&2
    return 0
  fi
  if [ ! -f "$readme" ]; then
    echo "error: $dir missing README.md" >&2
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

  local rendered_file
  rendered_file="$(mktemp)"
  render_tables "$docs" > "$rendered_file"
  inject "$readme" "$rendered_file"
  rm -f "$rendered_file"
  echo "ok: $readme" >&2
}

process_all() {
  for d in kustomize/*/; do
    process_dir "$d"
  done
}

usage() {
  cat >&2 <<'USAGE'
usage:
  kustomize-docs.sh kustomize/<add-on>     # one add-on
  kustomize-docs.sh --all                  # every add-on with .docs.yaml
  kustomize-docs.sh --check                # CI: fail on drift
USAGE
  exit 2
}

main() {
  # The kustomize/*/ glob below is relative to PWD. Without this guard, a
  # subdirectory invocation would expand to nothing and --check would exit 0
  # while real drift sits untested.
  [[ -d kustomize ]] || {
    echo "error: run kustomize-docs.sh from the repo root" >&2
    exit 1
  }

  case "${1:-}" in
    "")
      usage
      ;;
    --all)
      process_all
      ;;
    --check)
      process_all
      if ! git diff --exit-code -- 'kustomize/*/README.md'; then
        echo "error: kustomize-docs produced drift. Run 'task docs:kustomize' and commit the result." >&2
        exit 1
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      process_dir "$1"
      ;;
  esac
}

main "$@"
