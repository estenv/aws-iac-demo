#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Deletes asynchronously; the teardown gate accepts DELETE_IN_PROGRESS.
aws cloudformation delete-stack --stack-name cf-autoscaling
echo "cf-autoscaling deletion started (not waiting for completion)"
