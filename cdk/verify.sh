#!/usr/bin/env bash
# Usage: ./verify.sh {deploy|teardown}
set -uo pipefail
cd "$(dirname "$0")"
# shellcheck source=verify.conf
source ./verify.conf

FAILED=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; FAILED=1; }

assert_eq() { # desc expected actual
  if [[ "$2" == "$3" ]]; then ok "$1 ($3)"; else bad "$1 (expected '$2', got '$3')"; fi
}

assert_num_eq() { # desc expected actual (numeric compare)
  if awk -v a="$2" -v b="$3" 'BEGIN { exit !(a == b) }'; then
    ok "$1 ($3)"
  else
    bad "$1 (expected '$2', got '$3')"
  fi
}

# ---------------------------------------------------------------- deploy gate
verify_deploy() {
  echo "== $TOOL :: deploy gate =="

  local alb_arn dns tg_arn asg_json desired i state

  # 1. ALB exists, is active.
  alb_arn=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
  if [[ -z "$alb_arn" || "$alb_arn" == "None" ]]; then
    bad "ALB $ALB_NAME exists"
    return
  fi
  ok "ALB $ALB_NAME exists"
  aws elbv2 wait load-balancer-available --load-balancer-arns "$alb_arn"
  state=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
    --query 'LoadBalancers[0].State.Code' --output text)
  assert_eq "ALB state" active "$state"

  dns=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
    --query 'LoadBalancers[0].DNSName' --output text)
  echo "  ALB DNS: $dns"

  tg_arn=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

  # 2. Healthy targets equal the ASG desired capacity (poll up to 5 min).
  desired=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
  local healthy registered
  healthy=0
  for i in $(seq 1 60); do
    healthy=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" \
      --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' --output text)
    registered=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" \
      --query 'length(TargetHealthDescriptions)' --output text)
    if [[ "$healthy" -eq "$desired" && "$registered" -eq "$desired" ]]; then break; fi
    sleep 5
  done
  assert_eq "registered targets == desired" "$desired" "$registered"
  assert_eq "healthy targets == desired" "$desired" "$healthy"

  # 3. HTTP end to end, three times each.
  local code body
  for i in 1 2 3; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' "http://$dns/health.php" 2>/dev/null || true)
    assert_eq "health.php attempt $i" 200 "$code"
  done
  for i in 1 2 3; do
    body=$(curl -sS "http://$dns/index.php" 2>/dev/null || true)
    if [[ -n "$body" && "$body" == *"$INDEX_GREP"* ]]; then
      ok "index.php attempt $i contains '$INDEX_GREP'"
    else
      bad "index.php attempt $i (body: '${body:0:120}')"
    fi
  done
  echo "  sample index.php body: $body"

  # 4. ASG shape.
  asg_json=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --output json)
  assert_eq "ASG MinSize"    1 "$(jq -r '.AutoScalingGroups[0].MinSize'     <<<"$asg_json")"
  assert_eq "ASG MaxSize"    3 "$(jq -r '.AutoScalingGroups[0].MaxSize'     <<<"$asg_json")"
  assert_eq "ASG Desired"    1 "$(jq -r '.AutoScalingGroups[0].DesiredCapacity' <<<"$asg_json")"
  assert_eq "ASG HealthCheckType" ELB "$(jq -r '.AutoScalingGroups[0].HealthCheckType' <<<"$asg_json")"
  if jq -e --arg arn "$tg_arn" '.AutoScalingGroups[0].TargetGroupARNs | index($arn)' <<<"$asg_json" >/dev/null; then
    ok "ASG references target group"
  else
    bad "ASG does not reference target group $tg_arn"
  fi

  # 5. Alarms. CDK generates their names, so find them via the metric.
  local alarms
  alarms=$(aws cloudwatch describe-alarms-for-metric \
    --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value="$ASG_NAME" --output json)
  assert_eq "alarm count" 2 "$(jq '.MetricAlarms | length' <<<"$alarms")"
  assert_num_eq "scale-out alarm threshold" 40 "$(jq -r '.MetricAlarms[] | select(.Threshold == 40) | .Threshold' <<<"$alarms")"
  assert_num_eq "scale-in alarm threshold"  10 "$(jq -r '.MetricAlarms[] | select(.Threshold == 10) | .Threshold' <<<"$alarms")"
  assert_eq "scale-out alarm period" 300 "$(jq -r '.MetricAlarms[] | select(.Threshold == 40) | .Period' <<<"$alarms")"
  assert_eq "scale-in alarm period"  300 "$(jq -r '.MetricAlarms[] | select(.Threshold == 10) | .Period' <<<"$alarms")"
  assert_eq "scale-out alarm eval periods" 1 "$(jq -r '.MetricAlarms[] | select(.Threshold == 40) | .EvaluationPeriods' <<<"$alarms")"
  assert_eq "scale-in alarm eval periods"  1 "$(jq -r '.MetricAlarms[] | select(.Threshold == 10) | .EvaluationPeriods' <<<"$alarms")"

  # 6. Step scaling policies.
  local pol
  pol=$(aws autoscaling describe-policies --auto-scaling-group-name "$ASG_NAME" --output json)
  assert_eq "StepScaling policy count" 2 "$(jq '[.ScalingPolicies[] | select(.PolicyType=="StepScaling")] | length' <<<"$pol")"
  if jq -e '[.ScalingPolicies[].StepAdjustments[].ScalingAdjustment] | index(1)' <<<"$pol" >/dev/null; then
    ok "scale-out adjustment +1 present"
  else
    bad "scale-out adjustment +1 missing"
  fi
  if jq -e '[.ScalingPolicies[].StepAdjustments[].ScalingAdjustment] | index(-1)' <<<"$pol" >/dev/null; then
    ok "scale-in adjustment -1 present"
  else
    bad "scale-in adjustment -1 missing"
  fi

  # 7. ALB security group ingress limited to the deploying host's /32.
  local myip sg_ingress
  myip=$(curl -sS https://checkip.amazonaws.com 2>/dev/null || true)
  sg_ingress=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${PREFIX}-alb-sg" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`].IpRanges[].CidrIp' --output text)
  if [[ "$sg_ingress" == "$myip/32" ]]; then
    ok "ALB SG ingress limited to the deploying host /32"
  else
    bad "ALB SG ingress is not the deploying host /32"
  fi

  # 8. No IAM created: launch template has no instance profile.
  local lt_profile lt_key
  lt_profile=$(aws ec2 describe-launch-template-versions --launch-template-name "$LT_NAME" \
    --versions '$Latest' --query 'LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile' --output text)
  assert_eq "launch template has no instance profile" "None" "$lt_profile"
  lt_key=$(aws ec2 describe-launch-template-versions --launch-template-name "$LT_NAME" \
    --versions '$Latest' --query 'LaunchTemplateVersions[0].LaunchTemplateData.KeyName' --output text)
  assert_eq "launch template has no key pair" "None" "$lt_key"

  # 9. Tag-based discovery returns our resources.
  local tagged
  tagged=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=ProvisionedBy,Values=$TOOL \
    --query 'ResourceTagMappingList[].ResourceARN' --output json)
  if [[ "$(jq 'length' <<<"$tagged")" -gt 0 ]]; then
    ok "tags discover ProvisionedBy=$TOOL resources ($(jq 'length' <<<"$tagged"))"
  else
    bad "no resources tagged ProvisionedBy=$TOOL"
  fi

  # Instance scaling is out of scope; desired capacity is never changed.

  echo "== $TOOL :: deploy gate $([[ $FAILED -eq 0 ]] && echo PASSED || echo FAILED) =="
}

# -------------------------------------------------------------- teardown gate
# A stack that is gone or in DELETE_IN_PROGRESS counts as torn down.
verify_teardown() {
  echo "== $TOOL :: teardown gate =="

  local status
  if status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
      --query 'Stacks[0].StackStatus' --output text 2>/dev/null); then
    case "$status" in
      DELETE_IN_PROGRESS | DELETE_COMPLETE)
        ok "stack $STACK_NAME is being deleted ($status)"
        ;;
      *)
        bad "stack $STACK_NAME still exists ($status)"
        ;;
    esac
  else
    ok "stack $STACK_NAME is gone"
  fi

  echo "== $TOOL :: teardown gate $([[ $FAILED -eq 0 ]] && echo PASSED || echo FAILED) =="
}

case "${1:-}" in
  deploy)   verify_deploy ;;
  teardown) verify_teardown ;;
  *) echo "usage: $0 {deploy|teardown}" >&2; exit 2 ;;
esac

exit $FAILED
