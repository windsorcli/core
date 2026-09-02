#!/bin/bash

# Waits for every HelmRelease to reach Ready=True once, dropping each from
# the poll set as it converges. Kustomization readiness is windsor's own
# `--wait` flag; this covers HelmReleases nested in a Kustomization whose
# own health checks don't include them.
#
# Usage: wait-for-ready.sh [timeout_seconds] [poll_interval_seconds]

set -euo pipefail

TIMEOUT_SECONDS="${1:-300}"
POLL_INTERVAL="${2:-5}"

declare -A converged
elapsed=0

while true; do
  objects=$(windsor exec -- kubectl get helmreleases -A -o json)
  total=$(echo "$objects" | jq '.items | length')

  while IFS=$'\t' read -r key ready; do
    [ -z "$key" ] && continue
    if [ "$ready" = "True" ]; then
      converged["$key"]=1
    fi
  done < <(echo "$objects" | jq -r '
    .items[] | select(.status.observedGeneration == .metadata.generation) |
    "\(.kind)/\(.metadata.namespace)/\(.metadata.name)\t" +
    ((.status.conditions // [])[] | select(.type == "Ready") | .status)
  ')

  if [ "${#converged[@]}" -ge "$total" ] && [ "$total" -gt 0 ]; then
    echo "All $total resources reached Ready (after ${elapsed}s)."
    exit 0
  fi

  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "Timed out after ${TIMEOUT_SECONDS}s: ${#converged[@]}/$total resources reached Ready."
    echo "Not yet ready:"
    echo "$objects" | jq -r '
      .items[] |
      "\(.kind)/\(.metadata.namespace)/\(.metadata.name)\t" +
      (((.status.conditions // [])[] | select(.type == "Ready") | .status + ": " + .message) // "no Ready condition")
    ' | while IFS=$'\t' read -r key status; do
      [ -z "${converged[$key]:-}" ] && echo "  $key -> $status"
    done
    exit 1
  fi

  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))
done
