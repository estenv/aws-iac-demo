#!/usr/bin/env bash
#
# Deploy all three IaC variants and report the headline number for the demo:
# the time from starting each deploy until the load balancer first answers
# GET /health.php with HTTP 200.
#
# This deliberately does NOT run the per-tool verification gates. It only
# measures "time to first successful load balancer response", which is the
# number we want to show on screen.
#
# Usage: ./deploy-all.sh [--parallel]
set -uo pipefail
cd "$(dirname "$0")"

TOOLS=(cloudformation cdk terraform)
HEALTH_PATH="/health.php"
# Give up polling a tool after this many seconds.
POLL_DEADLINE=1800

PARALLEL=0
case "${1:-}" in
  "" | --sequential) : ;;
  --parallel) PARALLEL=1 ;;
  *) echo "usage: $0 [--parallel]" >&2; exit 2 ;;
esac

alb_name() {
  case "$1" in
    cloudformation) echo cf-alb ;;
    cdk)            echo cdk-alb ;;
    terraform)      echo tf-alb ;;
  esac
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/deploy-all.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

now() { date +%s.%N; }

fmt_dur() { # seconds (fractional) -> 3m42s
  awk -v s="$1" 'BEGIN {
    if (s < 60)        printf "%ds", s;
    else if (s < 3600) printf "%dm%02ds", int(s/60), int(s%60);
    else               printf "%dh%02dm", int(s/3600), int((s%3600)/60);
  }'
}

# Deploy one tool and poll its ALB until GET /health.php returns 200.
# Writes "tool|rc|deploy_secs|curl_secs|dns" to $TMP/<tool>.result.
measure_deploy() {
  local tool="$1"
  local alb log rcf out t0 dpid rc="" dns="" code curl_secs="" deploy_secs=""
  alb=$(alb_name "$tool")
  log="$TMP/$tool.log"
  rcf="$TMP/$tool.rc"
  out="$TMP/$tool.result"

  t0=$(now)
  # Run deploy.sh; record its exit code to a file so we can detect completion
  # without depending on how the shell reports finished background jobs.
  ( ( cd "$tool" && ./deploy.sh ) >"$log" 2>&1; echo $? >"$rcf" ) &
  dpid=$!

  local deadline
  deadline=$(( $(date +%s) + POLL_DEADLINE ))
  while :; do
    if [[ -z "$deploy_secs" && -f "$rcf" ]]; then
      rc=$(cat "$rcf")
      deploy_secs=$(awk -v a="$t0" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}')
    fi

    if [[ -z "$dns" ]]; then
      dns=$(aws elbv2 describe-load-balancers --names "$alb" \
        --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || true)
      [[ "$dns" == "None" ]] && dns=""
    fi

    if [[ -n "$dns" ]]; then
      code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 \
        "http://$dns$HEALTH_PATH" 2>/dev/null || true)
      if [[ "$code" == "200" ]]; then
        curl_secs=$(awk -v a="$t0" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}')
        break
      fi
    fi

    # A failed deploy can never produce a working endpoint; stop early.
    if [[ -n "$deploy_secs" && "${rc:-0}" != "0" ]]; then break; fi
    (( $(date +%s) >= deadline )) && break
    sleep 1
  done

  wait "$dpid" 2>/dev/null || true
  [[ -z "$deploy_secs" ]] && deploy_secs=$(awk -v a="$t0" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}')
  # curl can win before deploy.sh's exit code is written; read it now that the
  # job has actually finished.
  [[ -z "${rc:-}" ]] && rc=$(cat "$rcf" 2>/dev/null || echo 1)

  printf '%s|%s|%s|%s|%s\n' \
    "$tool" "$rc" "$deploy_secs" "${curl_secs:--}" "${dns:--}" >"$out"
}

# Emit one "time|tool|rc|deploy_secs|curl_secs|dns" row per tool, fastest first.
sorted_results() {
  local t key
  for t in "${TOOLS[@]}"; do
    IFS='|' read -r _ rc dsec csec dns < "$TMP/$t.result" || continue
    key="$csec"
    [[ "$csec" == "-" ]] && key=9999999
    printf '%s|%s|%s|%s|%s|%s\n' "$key" "$t" "$rc" "$dsec" "$csec" "$dns"
  done | sort -t'|' -k1,1 -g
}

print_summary() {
  local wall="$1" mode="$2"

  echo
  echo "=================================================================="
  echo "  Time to first successful load balancer response"
  echo "  GET $HEALTH_PATH -> HTTP 200, measured from the start of deploy"
  echo "=================================================================="

  local any_fail=0
  while IFS='|' read -r key t rc dsec csec dns; do
    local status shown
    if [[ "$csec" == "-" ]]; then
      status="FAIL"; shown="no successful response"; any_fail=1
    else
      shown="first 200 $(fmt_dur "$csec")"
      if [[ "$rc" -eq 0 ]]; then
        status="PASS"
      else
        status="PART"; any_fail=1
      fi
    fi
    printf '  %-4s  %-14s  %-22s  (deploy.sh %s)\n' \
      "$status" "$t" "$shown" "$(fmt_dur "$dsec")"
  done < <(sorted_results)

  echo "------------------------------------------------------------------"
  printf '  wall clock: %s (%s)\n' "$(fmt_dur "$wall")" "$mode"
  echo "=================================================================="
  echo "  load balancers:"
  local t dns
  for t in "${TOOLS[@]}"; do
    IFS='|' read -r _ _ _ _ dns < "$TMP/$t.result" || dns="-"
    printf '    %-14s http://%s%s\n' "$t" "$dns" "$HEALTH_PATH"
  done
  echo "=================================================================="

  if [[ $any_fail -ne 0 ]]; then
    local log
    for t in "${TOOLS[@]}"; do
      IFS='|' read -r _ rc _ csec _ < "$TMP/$t.result" || continue
      if [[ "$csec" == "-" || "$rc" -ne 0 ]]; then
        echo
        echo "  --- $t deploy.sh log (last 8 lines) ---"
        tail -n 8 "$TMP/$t.log" 2>/dev/null | sed 's/^/    /'
      fi
    done
  fi

  return $any_fail
}

started_at=$(now)
echo "Deploying: ${TOOLS[*]}"
if [[ $PARALLEL -eq 1 ]]; then
  echo "Mode: parallel race"
else
  echo "Mode: sequential"
fi

if [[ $PARALLEL -eq 1 ]]; then
  pids=()
  for t in "${TOOLS[@]}"; do measure_deploy "$t" & pids+=("$!"); done
  for p in "${pids[@]}"; do wait "$p"; done
else
  for t in "${TOOLS[@]}"; do
    echo
    echo "== deploying $t =="
    measure_deploy "$t"
    IFS='|' read -r _ _ dsec csec _ < "$TMP/$t.result"
    if [[ "$csec" == "-" ]]; then
      echo "  $t: no successful response"
    else
      echo "  $t: first 200 after $(fmt_dur "$csec")"
    fi
  done
fi

wall=$(awk -v a="$started_at" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}')
mode="sequential"
[[ $PARALLEL -eq 1 ]] && mode="parallel"
print_summary "$wall" "$mode"
exit $?
