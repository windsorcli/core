#!/usr/bin/env bash
#
# guide-scaffold.sh - Materialize the auto-derivable parts of a Catalog
# guide (docs/guides/<key>.md): a "## Configuration" table from schema.yaml,
# and a "## Reference" list of GitHub links to every Terraform module and
# Kustomize add-on gated on that schema key across contexts/_template/facets/.
#
# The rest of a guide — the intro, diagrams, "Under the hood" narrative —
# stays hand-authored. This only ever touches the two marked regions below,
# the same convention terraform-docs and kustomize-docs.sh already use.
#
# Usage:
#   scripts/guide-scaffold.sh <schema-key>   # one guide, e.g. database
#   scripts/guide-scaffold.sh --all          # every guide that already exists
#   scripts/guide-scaffold.sh --check        # CI: fail if any guide has drifted
#
# How a schema key resolves to real paths (see docs/guides/README.md):
#   - Terraform: every facets/*.yaml `terraform:` entry whose own `when:`
#     (facets have no top-level gate for terraform — each entry carries its
#     own) mentions the key contributes its `path:`.
#   - Kustomize: every facets/*.yaml `flux:` entry whose effective `when:`
#     (its own, or the facet's top-level `when:` if it has none) mentions
#     the key contributes `kustomize/<path-or-name>`, refined to
#     `kustomize/<path-or-name>/<component>` when that literal component
#     name is itself a real directory with its own README.
#
# This is a heuristic, not a schema: `test($key)` is a plain substring match
# against the `when:` string, so a very generic key name could over-match.
# Review the generated block same as you'd review a terraform-docs diff.
#
# Requires: yq v4 (mikefarah), jq.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$ROOT/contexts/_template/schema.yaml"
FACETS_DIR="$ROOT/contexts/_template/facets"
KUSTOMIZE_DIR="$ROOT/kustomize"
GUIDES_DIR="$ROOT/docs/guides"
REPO_URL="https://github.com/windsorcli/core/tree/main"

KNOBS_BEGIN='<!-- BEGIN_GUIDE_KNOBS -->'
KNOBS_END='<!-- END_GUIDE_KNOBS -->'
REFS_BEGIN='<!-- BEGIN_GUIDE_REFS -->'
REFS_END='<!-- END_GUIDE_REFS -->'

# ── Knobs ───────────────────────────────────────────────────────────────
# Flatten every leaf under .properties.<key> in schema.yaml into a
# key/type/default/enum/description row, dotted-path relative to the
# section root.
render_knobs() {
  local key="$1"
  local subtree
  subtree="$(yq -o=json ".properties.${key}" "$SCHEMA")"
  if [[ "$subtree" == "null" ]]; then
    echo "guide-scaffold: no schema.yaml property named '${key}'" >&2
    return 1
  fi

  local rows
  rows="$(jq -r --arg root "$key" '
    def esc: gsub("\\|"; "\\|");
    def leaves(prefix):
      if (.properties? != null) then
        (.properties | to_entries[] | (.key as $k | .value | leaves(prefix + [$k])))
      else
        {
          key: (prefix | join(".")),
          type: (.type // "object"),
          default: ((if .default == null then "—" else .default end) | tostring | esc),
          enum: (if .enum then (.enum | join(", ") | esc) else null end),
          description: ((.description // "—") | esc)
        }
      end;
    (leaves([$root]) | [
      "| `" + .key + "` | " + .type + " | `" + .default + "` | "
        + (.description | if test("[.!?]$") then . else . + "." end)
        + (if .enum then " One of: " + .enum + "." else "" end) + " |"
    ] | .[])
  ' <<<"$subtree")"

  if [[ -z "$rows" ]]; then
    echo "guide-scaffold: '${key}' has no leaf properties to render" >&2
    return 1
  fi

  printf '%s\n\n' "$KNOBS_BEGIN"
  echo '| Key | Type | Default | Description |'
  echo '|-----|------|---------|-------------|'
  printf '%s\n' "$rows"
  printf '\n%s\n' "$KNOBS_END"
}

# ── Reference ───────────────────────────────────────────────────────────
# Every quoted literal inside a `${ cond ? 'a' : 'b' }` template, or the
# whole value verbatim when it isn't templated at all.
extract_literals() {
  local val="$1"
  if [[ "$val" == '${'*'}'* ]]; then
    grep -oE "'[^']+'" <<<"$val" | tr -d "'" | grep -v '^$' || true
  elif [[ -n "$val" && "$val" != "null" ]]; then
    echo "$val"
  fi
}

render_refs() {
  local key="$1"
  local tf_paths=() kz_bases=() kz_literals=()

  local facet
  for facet in "$FACETS_DIR"/*.yaml; do
    [[ -f "$facet" ]] || continue
    local json
    json="$(yq -o=json "$facet" 2>/dev/null)" || continue

    while IFS= read -r p; do
      [[ -n "$p" ]] && tf_paths+=("$p")
    done < <(jq -r --arg key "$key" '
      .terraform[]? | select((.when // "") | test($key)) | .path
    ' <<<"$json")

    while IFS=$'\t' read -r base literal; do
      [[ -n "$base" ]] && kz_bases+=("$base")
      [[ -n "$literal" ]] && kz_literals+=("$base"$'\t'"$literal")
    done < <(jq -r --arg key "$key" '
      .when as $topwhen |
      .flux[]? |
      ((.when // $topwhen // "")) as $eff |
      select($eff | test($key)) |
      (.path // .name) as $base |
      (
        [ (.install.components // [])[], ([.resources[]? | (.components // [])[]]) ] | flatten
      ) as $comps |
      if ($comps | length) == 0 then
        $base + "\t"
      else
        $comps[] | $base + "\t" + .
      end
    ' <<<"$json")
  done

  # Resolve each (base, literal) pair to the most specific real directory:
  # kustomize/<base>/<component> if it has its own README, else kustomize/<base>.
  local kz_refs=()
  local pair base literal candidate
  for pair in "${kz_literals[@]}"; do
    base="${pair%%$'\t'*}"
    literal="${pair#*$'\t'}"
    if [[ -z "$literal" ]]; then
      kz_refs+=("$base")
      continue
    fi
    local lit
    while IFS= read -r lit; do
      [[ -z "$lit" ]] && continue
      candidate="$KUSTOMIZE_DIR/$base/$lit"
      if [[ -f "$candidate/README.md" ]]; then
        kz_refs+=("$base/$lit")
      else
        kz_refs+=("$base")
      fi
    done < <(extract_literals "$literal")
  done
  for base in "${kz_bases[@]}"; do
    # A matched entry with no components at all still counts as a reference
    # to its own add-on.
    :
  done

  local tf_sorted kz_sorted
  tf_sorted="$(printf '%s\n' "${tf_paths[@]:-}" | grep -v '^$' | sort -u || true)"
  kz_sorted="$(printf '%s\n' "${kz_refs[@]:-}" | grep -v '^$' | sort -u || true)"

  printf '%s\n\n' "$REFS_BEGIN"
  if [[ -n "$tf_sorted" ]]; then
    while IFS= read -r p; do
      echo "- [terraform/${p}](${REPO_URL}/terraform/${p}) on GitHub"
    done <<<"$tf_sorted"
  fi
  if [[ -n "$kz_sorted" ]]; then
    while IFS= read -r p; do
      echo "- [kustomize/${p}](${REPO_URL}/kustomize/${p}) on GitHub"
    done <<<"$kz_sorted"
  fi
  printf '\n%s\n' "$REFS_END"
}

# ── Splice a generated block into a guide file ─────────────────────────
splice() {
  local file="$1" begin="$2" end="$3" content="$4"
  if ! grep -qF "$begin" "$file" || ! grep -qF "$end" "$file"; then
    echo "guide-scaffold: $file has no $begin / $end markers — add them once by hand, regeneration takes it from there" >&2
    return 1
  fi
  local content_file tmp
  content_file="$(mktemp)"
  tmp="$(mktemp)"
  printf '%s' "$content" > "$content_file"
  awk -v begin="$begin" -v end="$end" -v contentfile="$content_file" '
    $0 == begin { while ((getline line < contentfile) > 0) print line; close(contentfile); skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  rm -f "$content_file"
}

update_guide() {
  local key="$1"
  local file="$GUIDES_DIR/${key}.md"
  if [[ ! -f "$file" ]]; then
    echo "guide-scaffold: no docs/guides/${key}.md yet — write the guide's intro/diagram/'Under the hood' by hand first, with $KNOBS_BEGIN/$KNOBS_END and $REFS_BEGIN/$REFS_END markers where the generated content goes" >&2
    return 1
  fi
  local knobs refs
  knobs="$(render_knobs "$key")"
  refs="$(render_refs "$key")"
  splice "$file" "$KNOBS_BEGIN" "$KNOBS_END" "$knobs"
  splice "$file" "$REFS_BEGIN" "$REFS_END" "$refs"
}

main() {
  local mode="${1:-}"
  case "$mode" in
    --all)
      local f key
      for f in "$GUIDES_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        key="$(basename "$f" .md)"
        update_guide "$key"
      done
      ;;
    --check)
      local f key tmp_repo
      tmp_repo="$(mktemp -d)"
      cp -r "$ROOT/." "$tmp_repo/"
      ( cd "$tmp_repo" && bash scripts/guide-scaffold.sh --all )
      if ! diff -rq "$GUIDES_DIR" "$tmp_repo/docs/guides" >/dev/null; then
        echo "guide-scaffold --check: one or more guides have drifted from schema.yaml/facets. Run scripts/guide-scaffold.sh --all and commit the result." >&2
        diff -ru "$GUIDES_DIR" "$tmp_repo/docs/guides" || true
        rm -rf "$tmp_repo"
        exit 1
      fi
      rm -rf "$tmp_repo"
      ;;
    ""|--help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      update_guide "$mode"
      ;;
  esac
}

main "$@"
