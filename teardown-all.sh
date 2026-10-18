#!/usr/bin/env bash
#
# Tear down all three IaC variants.
#
# No verification gates are run here, and teardown timing is deliberately not
# reported as a comparable number: CloudFormation's destroy.sh returns as soon
# as the delete is issued, CDK and Terraform block until their deletes finish,
# so a cross-tool "duration" would not be meaningful.
#
# Usage: ./teardown-all.sh [--parallel]
set -uo pipefail
cd "$(dirname "$0")"

TOOLS=(cloudformation cdk terraform)

PARALLEL=0
case "${1:-}" in
  "" | --sequential) : ;;
  --parallel) PARALLEL=1 ;;
  *) echo "usage: $0 [--parallel]" >&2; exit 2 ;;
esac

TMP=$(mktemp -d "${TMPDIR:-/tmp}/teardown-all.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

rc=0

if [[ $PARALLEL -eq 1 ]]; then
  echo "Tearing down in parallel: ${TOOLS[*]}"
  echo
  declare -A pid
  for t in "${TOOLS[@]}"; do
    ( cd "$t" && ./destroy.sh ) >"$TMP/$t.log" 2>&1 &
    pid[$t]=$!
  done
  for t in "${TOOLS[@]}"; do
    if wait "${pid[$t]}"; then
      echo "  PASS  $t"
    else
      echo "  FAIL  $t"
      rc=1
      sed 's/^/    /' "$TMP/$t.log" 2>/dev/null
    fi
  done
else
  for t in "${TOOLS[@]}"; do
    echo "== tearing down $t =="
    if ( cd "$t" && ./destroy.sh ); then
      echo "  PASS  $t"
    else
      echo "  FAIL  $t"
      rc=1
    fi
  done
fi

echo
if [[ $rc -eq 0 ]]; then
  echo "Teardown issued for all three variants."
else
  echo "Teardown finished with failures (see above)."
fi
echo "Note: CloudFormation/CDK deletes continue asynchronously after this returns."

exit $rc
