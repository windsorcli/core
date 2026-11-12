#!/bin/bash

# Blocks egress from the workstation network, and reports each connection
# that tried to leave it. Use it on a Linux Docker host, after the
# workstation containers start.
#
# Usage:
#   egress.sh block   Reject and log each new connection from the network to
#                     a host outside it, except DNS. Then probe the block.
#   egress.sh check   Fail when the chain logged a connection, and list each
#                     destination with its count.
#
# Environment:
#   EGRESS_NETWORK  Docker network to block. Default: windsor-local.
#   EGRESS_DNS      DNS container on that network. Default: dns.test.
#   EGRESS_PROBE    Container that runs the probes. Default: charts.test.

set -euo pipefail

CHAIN="WINDSOR-EGRESS"
LOG_PREFIX="windsor-egress: "
NETWORK="${EGRESS_NETWORK:-windsor-local}"
DNS_CONTAINER="${EGRESS_DNS:-dns.test}"
PROBE="${EGRESS_PROBE:-charts.test}"

block() {
  local cidr dns
  cidr="$(docker network inspect "$NETWORK" -f '{{(index .IPAM.Config 0).Subnet}}')"
  dns="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$DNS_CONTAINER" | awk '{print $1}')"

  sudo iptables -N "$CHAIN"
  sudo iptables -A "$CHAIN" -d "$cidr" -j RETURN
  sudo iptables -A "$CHAIN" -p udp --dport 53 -j RETURN
  sudo iptables -A "$CHAIN" -p tcp --dport 53 -j RETURN
  sudo iptables -A "$CHAIN" -m conntrack ! --ctstate NEW -j RETURN
  sudo iptables -A "$CHAIN" -j REJECT
  sudo iptables -I DOCKER-USER -s "$cidr" -j "$CHAIN"

  # The probes must pass before the LOG rule goes in, so that they add no count.
  docker exec "$PROBE" nslookup git.test "$dns"
  docker exec "$PROBE" nslookup github.com "$dns"
  docker exec "$PROBE" nc -z -w 5 git.test 80
  if docker exec "$PROBE" wget -q -T 10 -O /dev/null https://github.com; then
    echo "::error::The workstation network reached https://github.com with egress blocked"
    exit 1
  fi

  sudo iptables -I "$CHAIN" 5 -j LOG --log-prefix "$LOG_PREFIX"
  sudo iptables -L "$CHAIN" -v -n
}

check() {
  local rules count
  rules="$(sudo iptables -L "$CHAIN" -v -x -n)"
  echo "$rules"
  count="$(awk '$3 == "LOG" {print $1}' <<< "$rules")"
  if [ "$count" = "0" ]; then
    echo "No connection left the workstation network."
    exit 0
  fi

  echo "::error::The cluster opened $count connections to hosts outside the workstation network"
  sudo dmesg \
    | sed -n "s/.*${LOG_PREFIX}.* SRC=\([^ ]*\) DST=\([^ ]*\) .* PROTO=\([^ ]*\) .*DPT=\([0-9]*\).*/\1 \2 \3\/\4/p" \
    | sort | uniq -c | sort -rn \
    | while read -r n src dst port; do
        echo "$n $src -> $dst $port $(getent hosts "$dst" | awk '{print $2}')"
      done
  exit 1
}

case "${1:-}" in
  block) block ;;
  check) check ;;
  *)
    echo "Usage: $0 block|check" >&2
    exit 2
    ;;
esac
