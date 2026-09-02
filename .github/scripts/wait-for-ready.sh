#!/bin/bash

# Waits for every HelmRelease to reach Ready=True once, dropping each from
# the poll set as it converges. Kustomization readiness is windsor's own
# `--wait` flag; this covers HelmReleases nested in a Kustomization whose
# own health checks don't include them.
#
# Usage: wait-for-ready.sh [timeout_seconds] [poll_interval_seconds]

# No -u: bash's nounset treats an empty associative array's ${#converged[@]}
# as unbound, and converged legitimately starts and can stay empty.
set -eo pipefail

TIMEOUT_SECONDS="${1:-300}"
POLL_INTERVAL="${2:-5}"

declare -A converged
objects='{"items":[]}'
total=0
elapsed=0

while true; do
  # A single tick's kubectl call can return a transient error or a partial
  # response. Skip this tick on either instead of aborting the whole poll.
  if fetched=$(windsor exec -- kubectl get helmreleases -A -o json) && jq empty <<< "$fetched" 2>/dev/null; then
    objects="$fetched"
    total=$(jq '.items | length' <<< "$objects")

    while IFS=$'\t' read -r key ready; do
      [ -z "$key" ] && continue
      if [ "$ready" = "True" ]; then
        converged["$key"]=1
      fi
    done < <(jq -r '
      .items[] | select(.status.observedGeneration == .metadata.generation) |
      "\(.kind)/\(.metadata.namespace)/\(.metadata.name)\t" +
      ((.status.conditions // [])[] | select(.type == "Ready") | .status)
    ' <<< "$objects")

    if [ "${#converged[@]}" -ge "$total" ] && [ "$total" -gt 0 ]; then
      echo "All $total resources reached Ready (after ${elapsed}s)."
      exit 0
    fi
  else
    echo "kubectl get helmreleases returned no valid JSON this tick, retrying."
  fi

  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "Timed out after ${TIMEOUT_SECONDS}s: ${#converged[@]}/$total resources reached Ready."
    echo "Not yet ready:"
    jq -r '
      .items[] |
      "\(.kind)/\(.metadata.namespace)/\(.metadata.name)\t" +
      (((.status.conditions // [])[] | select(.type == "Ready") | .status + ": " + .message) // "no Ready condition")
    ' <<< "$objects" | while IFS=$'\t' read -r key status; do
      [ -z "${converged[$key]:-}" ] && echo "  $key -> $status"
    done
    exit 1
  fi

  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))
done
