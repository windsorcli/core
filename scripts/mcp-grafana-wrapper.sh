#!/usr/bin/env bash
# Resolves GRAFANA_URL for the local dev Grafana before exec'ing mcp-grafana. The gateway
# host is reachable on a different port depending on the docker driver: docker-desktop
# remaps the gateway's HTTPS NodePort onto a non-standard host port (e.g. :8443, see
# `docker context ls` / `docker --context desktop-linux ps`); colima gives the node a
# routable IP so the same host answers on plain 443. Rather than hardcode either, probe
# both and use whichever responds. An explicit GRAFANA_URL in the environment always wins.
set -euo pipefail

if [ -z "${GRAFANA_URL:-}" ]; then
  for candidate in "https://grafana.test:8443" "https://grafana.test"; do
    if curl -sk -o /dev/null -m 2 "${candidate}/api/health"; then
      export GRAFANA_URL="${candidate}"
      break
    fi
  done
fi

exec mcp-grafana "$@"
