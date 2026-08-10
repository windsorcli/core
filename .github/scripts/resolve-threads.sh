#!/usr/bin/env bash
# Resolves the review threads listed in /tmp/resolve-thread-ids.txt, one GraphQL
# thread node ID per line. Runs inside the claude-code-action step, the only
# context whose token can resolve threads.
set -euo pipefail

IDS_FILE=/tmp/resolve-thread-ids.txt

if [ ! -s "$IDS_FILE" ]; then
  echo "No threads to resolve."
  exit 0
fi

failed=0
while IFS= read -r tid; do
  [ -n "$tid" ] || continue
  # shellcheck disable=SC2016  # $id is a GraphQL variable, passed via -F
  if err="$(gh api graphql -f query='
    mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id } } }' \
    -F id="$tid" 2>&1 >/dev/null)"; then
    echo "Resolved thread $tid"
  else
    echo "error: failed to resolve thread $tid: $err" >&2
    failed=$((failed + 1))
  fi
done < "$IDS_FILE"

if [ "$failed" -ne 0 ]; then
  echo "error: $failed thread(s) could not be resolved" >&2
  exit 1
fi
