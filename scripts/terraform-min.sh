#!/usr/bin/env bash
#
# terraform-min.sh - Fail if the Terraform minimum pins differ from the
# required_version floor declared by the modules under terraform/.
#
# Usage:
#   scripts/terraform-min.sh --check

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

floors="$(grep -rhoE --include='*.tf' 'required_version *= *">= *[0-9.]+"' terraform | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
if [ -z "$floors" ] || [ "$(echo "$floors" | wc -l)" -ne 1 ]; then
  echo "::error::terraform/ modules do not share one required_version floor: ${floors:-none found}"
  exit 1
fi

action_min="$(sed -n 's/^ *TERRAFORM_MIN: *//p' .github/actions/setup-tools/action.yml)"
aqua_min="$(sed -n 's|^ *- name: hashicorp/terraform@v||p' aqua.yaml)"

rc=0
if [ "$action_min" != "$floors" ]; then
  echo "::error::setup-tools TERRAFORM_MIN is '$action_min' but required_version floor is '$floors'"
  rc=1
fi
if [ "$aqua_min" != "$floors" ]; then
  echo "::error::aqua.yaml hashicorp/terraform is '$aqua_min' but required_version floor is '$floors'"
  rc=1
fi
[ $rc -eq 0 ] && echo "Terraform minimum $floors matches required_version, setup-tools, and aqua.yaml."
exit $rc
