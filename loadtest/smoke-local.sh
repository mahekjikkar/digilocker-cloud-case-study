#!/usr/bin/env bash
# Local smoke test of the k6 scenarios. No AWS involved.
#
# Starts the registry and both mock issuers on localhost, then runs E1-E4 with
# every duration shrunk (TIME_SCALE) through the same run.sh used for AWS runs.
# This checks that the scripts work, not that the architecture does: results
# land in loadtest/.smoke/ (git-ignored) and are never evidence for the report.
#
# E3 runs without terminating an instance (there is no ASG locally), so only
# its script and phase tagging are exercised.
#
# Usage: ./loadtest/smoke-local.sh
set -uo pipefail
cd "$(dirname "$0")/.."

command -v k6 >/dev/null || export PATH="$PATH:/c/Program Files/k6"
command -v k6 >/dev/null || { echo "k6 not found"; exit 1; }
k6 version | head -1

SMOKE=loadtest/.smoke
rm -rf "$SMOKE"; mkdir -p "$SMOKE"

PORTS="8000 9001 9002"
stop_all() {
  powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort ${PORTS// /,} -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }" >/dev/null 2>&1
}
trap stop_all EXIT
stop_all   # clear anything left from an earlier run

wait_for() { # url
  for _ in $(seq 1 30); do curl -s -m 2 -o /dev/null "$1" && return 0; sleep 1; done
  echo "timed out waiting for $1"; exit 1
}

( cd mock-issuer && ISSUER_ID=CBSE python -m uvicorn main:app --port 9001 >"../$SMOKE/cbse.log" 2>&1 & )
( cd mock-issuer && ISSUER_ID=PARIVAHAN python -m uvicorn main:app --port 9002 >"../$SMOKE/parivahan.log" 2>&1 & )
wait_for localhost:9001/health; wait_for localhost:9002/health

start_registry() { # on|off
  powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }" >/dev/null 2>&1
  sleep 1
  ( cd app && API_KEY=smoke BREAKER_ENABLED=$([ "$1" = on ] && echo true || echo false) \
      CBSE_URL=http://127.0.0.1:9001 PARIVAHAN_URL=http://127.0.0.1:9002 \
      python -m uvicorn main:app --port 8000 >"../$SMOKE/registry-$1.log" 2>&1 & )
  wait_for localhost:8000/health
}

export BASE_URL=http://localhost:8000 API_KEY=smoke
export CBSE_CONTROL_URL=http://localhost:9001 PARIVAHAN_CONTROL_URL=http://localhost:9002
export SKIP_BREAKER_SWITCH=1 SKIP_TERMINATE=1 RESULTS_ROOT="$SMOKE/results"

run() { # scale scenario [breaker]
  echo; echo "################ $2 ${3:-} (TIME_SCALE=$1)"
  TIME_SCALE=$1 ./loadtest/run.sh "$2" ${3:-} >"$SMOKE/$2-${3:-x}.out" 2>&1
  echo "exit code: $? (0 = thresholds met, 99 = a threshold failed, other = problem)"
}

# SCENARIOS="e3" ./loadtest/smoke-local.sh runs a subset. The registry is
# restarted before every scenario so one cannot inherit another's state.
for s in ${SCENARIOS:-e1 e2 e3 e4}; do
  case $s in
    e1) start_registry off; run 0.15 e1 ;;
    e2) start_registry off; run 0.05 e2 ;;
    e3) start_registry off; run 0.1 e3 ;;
    e4) start_registry off; run 0.15 e4 off
        start_registry on;  run 0.15 e4 on ;;
    *)  echo "unknown scenario $s" ;;
  esac
done

echo
echo "################ digest: E4 per-issuer, per-phase results"
E4_DIRS=$(ls -d "$SMOKE"/results/*e4-breaker-* 2>/dev/null)
[ -n "$E4_DIRS" ] && python -I loadtest/digest.py $E4_DIRS
echo "full output per run: $SMOKE/*.out   raw results: $SMOKE/results/"
