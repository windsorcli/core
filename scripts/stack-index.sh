#!/usr/bin/env bash
#
# stack-index.sh - Materialize the BEGIN_STACK_INDEX / END_STACK_INDEX region
# of docs/index.md from the terraform/ and kustomize/ directory trees.
#
# Usage:
#   scripts/stack-index.sh          # regen the stack index
#   scripts/stack-index.sh --check  # CI: fail on drift
#
# Model: terraform/ is the "Infrastructure" half, kustomize/ is the
# "Cluster" half. Each immediate subdirectory of either is a "layer" (e.g.
# terraform/database, kustomize/identity). A layer with at least one
# README.md anywhere under it must have a README.md AT ITS OWN ROOT, with
# `stack_backing:` frontmatter (and optionally `stack_name:` to override the
# auto-derived display name, e.g. `CNI` instead of `Cni`) — that root is
# always what the layer links to, regardless of how many nested modules
# exist underneath it. A layer with no README.md anywhere is skipped
# silently: it has nothing written about it yet, so it has nothing to index.
#
# This intentionally does not try to preserve hand-picked ordering — output
# is alphabetical by layer name within each half, which is what makes the
# check idempotent without a side-channel ordering file.

set -euo pipefail

BEGIN_MARKER='<!-- BEGIN_STACK_INDEX -->'
END_MARKER='<!-- END_STACK_INDEX -->'
INDEX_FILE='docs/index.md'
NL_PLACEHOLDER='@@STACK_NL@@'

# Extract frontmatter field $2 from file $1. Empty string if absent.
extract_field() {
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

# Sentence-case a hyphenated dirname: "object-store" -> "Object store".
default_name() {
  local s="${1//-/ }"
  printf '%s%s' "$(echo "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"
}

# Build one half's layer blocks and print them to stdout, sorted by layer
# name. $1 = engine dir (terraform|kustomize). Sets $BUILD_HALF_ERRORS.
# No pipe from the for loop (that would fork a subshell and lose error
# tracking) — entries are collected into an array in this shell, sorted
# with each layer kept as one atomic record via NL_PLACEHOLDER, then
# expanded back to real newlines on the way out.
build_half() {
  local engine="$1"
  local entries=()
  BUILD_HALF_ERRORS=0

  for dir in "$engine"/*/; do
    local category root_readme
    category="$(basename "$dir")"
    root_readme="$engine/$category/README.md"

    if [ ! -f "$root_readme" ]; then
      if find "$dir" -name README.md -type f | grep -q .; then
        echo "error: $engine/$category has documented modules but no root README.md — add one with stack_backing frontmatter" >&2
        BUILD_HALF_ERRORS=1
      fi
      continue
    fi

    local backing name
    backing="$(extract_field "$root_readme" stack_backing)"
    name="$(extract_field "$root_readme" stack_name)"
    if [ -z "$backing" ]; then
      echo "error: $root_readme is missing stack_backing frontmatter" >&2
      BUILD_HALF_ERRORS=1
      continue
    fi
    [ -n "$name" ] || name="$(default_name "$category")"

    # Prefer linking the actual leaf modules below the category
    # (terraform/object-store/{aws,hetzner}, terraform/gitops/flux) — that's
    # where the real reference content (inputs/outputs/resources) lives, and
    # what a reader actually wants from this table. The category root is
    # metadata-only in that case: title/description/stack_backing, plus
    # whatever orienting prose it carries, but not itself a link target. Only
    # fall back to linking the root when nothing exists below it at all (a
    # true single-page add-on like kustomize/identity).
    #
    # terraform only: a leaf one level down with no README of its own
    # (terraform/dns/zone) is a pure grouping directory, not a module —
    # descend one more level for its real leaves (zone/route53,
    # zone/azure-dns) and list each under its group prefix. kustomize add-ons
    # never use directory-based leaf modules at all (their real breakdown
    # lives in .docs.yaml, surfaced separately on the Catalog page) — descending
    # there risks surfacing an unrelated nested file (a stray supplementary
    # README two directories down) as if it were the add-on's sole component.
    local leaves=() leaf_dir leaf
    for leaf_dir in "$dir"*/; do
      [ -d "$leaf_dir" ] || continue
      leaf="$(basename "$leaf_dir")"
      if [ -f "$engine/$category/$leaf/README.md" ]; then
        leaves+=("$leaf")
        continue
      fi
      [ "$engine" = "terraform" ] || continue
      local sub_dir sub
      for sub_dir in "$leaf_dir"*/; do
        [ -d "$sub_dir" ] || continue
        sub="$(basename "$sub_dir")"
        [ -f "$engine/$category/$leaf/$sub/README.md" ] && leaves+=("$leaf/$sub")
      done
    done

    # Links are relative to INDEX_FILE (docs/index.md, one level deep), not
    # the repo root — every target needs the ../ back up to it.
    local links=""
    if [ "${#leaves[@]}" -gt 0 ]; then
      IFS=$'\n' leaves=($(sort <<<"${leaves[*]}")); unset IFS
      for leaf in "${leaves[@]}"; do
        links+="- [$leaf](../$engine/$category/$leaf)$NL_PLACEHOLDER"
      done
      links="${links%$NL_PLACEHOLDER}"
    else
      links="- [$category](../$engine/$category)"
    fi

    entries+=("$name"$'\t'"### $name — $backing$NL_PLACEHOLDER$links")
  done

  if [ "${#entries[@]}" -gt 0 ]; then
    printf '%s\n' "${entries[@]}" \
      | sort -f -t $'\t' -k1,1 \
      | cut -f2- \
      | awk -v nl="$NL_PLACEHOLDER" '{ gsub(nl, "\n"); print; print "" }'
  fi
}

# Validate that $INDEX_FILE opens with an H1 and a non-empty lede paragraph
# before the Stack section. The site's parseIndex() only captures a
# blueprint's /catalog tile name and summary when it finds an H1 first,
# then a paragraph — missing either comes back as an empty string, with no
# build error, just a blank tile. Unlike every other README in this repo,
# this file's H1 is not a duplicate of the frontmatter title: it's parsed
# data, and a "strip the duplicate H1" pass must not touch it.
check_h1_and_lede() {
  local body h1_line lede_line
  body="$(awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; rest=1; next} rest' "$INDEX_FILE")"

  h1_line="$(printf '%s\n' "$body" | awk '/^$/{next} {print; exit}')"
  if [[ "$h1_line" != "# "* ]]; then
    echo "error: $INDEX_FILE must open with an H1 (# <Blueprint name>) right after its frontmatter — parseIndex() reads it for the /catalog tile name. Found: '${h1_line:-<empty>}'" >&2
    return 1
  fi

  lede_line="$(printf '%s\n' "$body" | awk -v begin="$BEGIN_MARKER" '
    seen_h1 { if ($0=="") next; if ($0 ~ /^#/ || $0==begin) exit; print; exit }
    /^# / { seen_h1=1 }
  ')"
  if [ -z "$lede_line" ]; then
    echo "error: $INDEX_FILE needs a lede paragraph between its H1 and the Stack section — parseIndex() reads it for the /catalog tile summary." >&2
    return 1
  fi
}

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

ERRORS=0
check_h1_and_lede || ERRORS=1
{
  echo "$BEGIN_MARKER"
  echo
  echo '## Infrastructure'
  echo
  build_half terraform
  [ "$BUILD_HALF_ERRORS" = 0 ] || ERRORS=1
  echo '## Cluster'
  echo
  build_half kustomize
  [ "$BUILD_HALF_ERRORS" = 0 ] || ERRORS=1
  echo "$END_MARKER"
} > "$TMP"

if [ "$ERRORS" != 0 ]; then
  echo "error: fix the above before regenerating $INDEX_FILE" >&2
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  if ! grep -q "$BEGIN_MARKER" "$INDEX_FILE"; then
    echo "error: $INDEX_FILE has no $BEGIN_MARKER region" >&2
    exit 1
  fi
  current="$(awk "/$BEGIN_MARKER/,/$END_MARKER/" "$INDEX_FILE")"
  new="$(cat "$TMP")"
  if [ "$current" != "$new" ]; then
    echo "error: docs/index.md's stack index is out of date. Run 'task docs:stack' and commit the result." >&2
    diff <(echo "$current") <(echo "$new") >&2 || true
    exit 1
  fi
  echo "ok: $INDEX_FILE stack index is current"
else
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v newfile="$TMP" '
    BEGIN { while ((getline line < newfile) > 0) repl = repl line "\n" }
    $0 == begin { printf "%s", repl; skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$INDEX_FILE" > "$INDEX_FILE.new" && mv "$INDEX_FILE.new" "$INDEX_FILE"
  echo "ok: regenerated $INDEX_FILE stack index"
fi
