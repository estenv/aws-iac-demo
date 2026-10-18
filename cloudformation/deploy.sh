#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

STACK=cf-autoscaling
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets \
  --filters Name=default-for-az,Values=true \
            Name=availability-zone,Values=us-east-1a,us-east-1b \
  --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
MYIP=$(curl -sS https://checkip.amazonaws.com)

echo "Default VPC:  $VPC"
echo "Subnets:      $SUBNETS"

aws cloudformation deploy \
  --stack-name "$STACK" \
  --template-file template.yaml \
  --no-fail-on-empty-changeset \
  --parameter-overrides VpcId="$VPC" SubnetIds="$SUBNETS" AllowedCidr="$MYIP/32"

aws cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].Outputs' --output table
