#!/usr/bin/env bash
# Resolves the PR review threads the agent step identified as addressed.
# The agent writes /tmp/resolve-thread-ids.txt (one GraphQL thread node ID
# per line, judgment already applied); this script does the actual
# resolveReviewThread mutation. Runs here — not in the model's sandbox — so
# a denied or malformed tool call in the agent step can never leave a
# thread silently unresolved, and a script bug can't silently mark a live
# finding as addressed (the agent's judgment call already happened).
#
# Required env: GH_TOKEN, GH_REPO (owner/repo).
set -euo pipefail

: "${GH_REPO:?}"

IDS_FILE=/tmp/resolve-thread-ids.txt

if [ ! -s "$IDS_FILE" ]; then
  echo "No threads to resolve."
  exit 0
fi

while IFS= read -r tid; do
  [ -n "$tid" ] || continue
  # shellcheck disable=SC2016  # $id is a GraphQL variable, passed via -F
  if gh api graphql -f query='
    mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id } } }' \
    -F id="$tid" > /dev/null; then
    echo "Resolved thread $tid"
  else
    echo "::warning::Failed to resolve thread $tid"
  fi
done < "$IDS_FILE"
