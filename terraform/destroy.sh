#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

terraform destroy -input=false -auto-approve
