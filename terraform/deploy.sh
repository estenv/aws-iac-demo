#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# The ALB only allows HTTP from the deploying host.
MYIP=$(curl -sS https://checkip.amazonaws.com)

terraform init -input=false
terraform apply -input=false -auto-approve -var "alb_ingress_cidr=$MYIP/32"
terraform output
