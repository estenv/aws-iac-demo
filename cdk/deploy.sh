#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Install the pinned dependencies.
npm ci

# The ALB only allows HTTP from the deploying host.
MYIP=$(curl -sS https://checkip.amazonaws.com)

npx cdk deploy cdk-autoscaling --require-approval never -c albIngressCidr="$MYIP/32"
