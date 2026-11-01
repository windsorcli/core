#!/usr/bin/env bash
# Resolves the review threads listed in /tmp/resolve-thread-ids.txt, one GraphQL
# thread node ID per line. Only IDs of this PR's unresolved bot threads resolve.
#
# Required env: GH_TOKEN, GH_REPO (owner/repo), PR_NUMBER.
set -euo pipefail

: "${GH_REPO:?}" "${PR_NUMBER:?}"

IDS_FILE=/tmp/resolve-thread-ids.txt

if [ ! -s "$IDS_FILE" ]; then
  echo "No threads to resolve."
  exit 0
fi

owner="${GH_REPO%/*}"
repo="${GH_REPO#*/}"
# shellcheck disable=SC2016  # $owner/$repo/$num are GraphQL variables, passed via -F
allowed="$(gh api graphql -f query='
  query($owner:String!,$repo:String!,$num:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$num){
        reviewThreads(first:100){ nodes{ id isResolved
          comments(first:1){ nodes{ author{ login } } } } } } } }' \
  -F owner="$owner" -F repo="$repo" -F num="$PR_NUMBER" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved==false)
        | select(.comments.nodes[0].author.login | test("\\[bot\\]$|^github-actions|^claude$"))
        | .id')"

failed=0
while IFS= read -r tid; do
  [ -n "$tid" ] || continue
  if ! grep -qxF "$tid" <<< "$allowed"; then
    echo "Skipping $tid: not an unresolved bot thread on PR #${PR_NUMBER}"
    continue
  fi
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
