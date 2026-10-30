#!/usr/bin/env bash
# Run one scenario against the deployed stack and save everything as produced.
#
# Usage: ./run.sh e1
#        ./run.sh e2
#        ./run.sh e3
#        ./run.sh e4 off      # E4 with the circuit breaker disabled
#        ./run.sh e4 on       # E4 with the circuit breaker enabled
#
# Output goes to results/aws/<UTC time>-<scenario>[-breaker-<mode>]/ :
#   run-info.txt    what ran, when, against what (no secrets)
#   <e>-raw.json.gz every k6 data point, timestamped
#   <e>-summary.json, k6-stdout.txt, k6-stderr.log   (stderr has INJECT/BREAKERS lines)
#   terminate.log   (E3 only) when the instance was killed
#
# Exit code 97 means the run is INVALID (stalled or far off its planned duration,
# see check_run.py), whatever k6 itself returned. Do not use or commit such a run.
#
# Nothing here edits results. A failed k6 threshold is recorded, not hidden:
# an unmet expectation is a finding.
#
# For a local smoke test, set BASE_URL, API_KEY and the control URLs yourself,
# plus SKIP_BREAKER_SWITCH=1 and SKIP_TERMINATE=1, and RESULTS_ROOT elsewhere.
set -uo pipefail
cd "$(dirname "$0")/.."   # repo root: k6 resolves relative paths from here

SCENARIO="${1:-}"
case "$SCENARIO" in
  e1) SCRIPT=loadtest/e1_baseline.js ;;
  e2) SCRIPT=loadtest/e2_ramp.js ;;
  e3) SCRIPT=loadtest/e3_instance_loss.js ;;
  e4) SCRIPT=loadtest/e4_degraded_issuer.js ;;
  *)  echo "usage: ./loadtest/run.sh e1|e2|e3|e4 [off|on]"; exit 1 ;;
esac

LABEL="$SCENARIO"
if [ "$SCENARIO" = "e4" ]; then
  BREAKER="${2:-}"
  [ "$BREAKER" = "on" ] || [ "$BREAKER" = "off" ] || { echo "e4 needs: off|on"; exit 1; }
  LABEL="e4-breaker-$BREAKER"
  export BREAKER
fi

command -v k6 >/dev/null || { echo "k6 not found on PATH (https://grafana.com/docs/k6/latest/set-up/install-k6/)"; exit 1; }

if [ -z "${BASE_URL:-}" ]; then
  set -a; source infra/.state.env; set +a   # stack not up? run infra/up.sh first
fi

if [ "$SCENARIO" = "e4" ] && [ -z "${SKIP_BREAKER_SWITCH:-}" ]; then
  # Restarts the registry service everywhere, so breaker state starts clean.
  infra/set-breaker.sh "$BREAKER" || { echo "could not switch breaker"; exit 1; }
fi

WARMUP=""
if [ "$SCENARIO" = "e4" ]; then
  # A freshly restarted registry stalls about 10 s on its first requests (lazy
  # DynamoDB client set-up), seen in E3 when a replacement instance joined. The
  # breaker switch restarts the service, so warm every instance, identically for
  # the off and on runs, so start-up cost is not mistaken for the effect under test.
  for i in $(seq 1 60); do
    curl -s -m 20 -o /dev/null -H "X-API-Key: $API_KEY" "$BASE_URL/documents/CBSE-MARKSHEET-0001" &
    curl -s -m 20 -o /dev/null -H "X-API-Key: $API_KEY" "$BASE_URL/documents/PARIVAHAN-DL-0001" &
  done
  wait
  sleep 5
  WARMUP="120 requests before the run (registry restarted by the breaker switch)"
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DIR="${RESULTS_ROOT:-results/aws}/$STAMP-$LABEL"
mkdir -p "$DIR"
export RESULTS_DIR="$DIR" RUN_LABEL="$LABEL"

{
  echo "scenario:   $LABEL"
  echo "started:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "commit:     $(git rev-parse --short HEAD) $(git diff --quiet || echo '(uncommitted changes)')"
  echo "target:     $BASE_URL"
  echo "k6:         $(k6 version | head -1)"
  echo "time scale: ${TIME_SCALE:-1}"
  [ -n "$WARMUP" ] && echo "warm-up:    $WARMUP"
  echo "region:     ap-south-1 (multi-zone, single region)"
} > "$DIR/run-info.txt"

if [ "$SCENARIO" = "e3" ] && [ -z "${SKIP_TERMINATE:-}" ]; then
  export KILL_AT="${KILL_AT:-90}"
  ( sleep "$KILL_AT"; infra/terminate-one.sh ) > "$DIR/terminate.log" 2>&1 &
  echo "instance will be terminated at +${KILL_AT}s"
fi

k6 run --out "json=$DIR/$SCENARIO-raw.json.gz" "$SCRIPT" \
  > >(tee "$DIR/k6-stdout.txt") 2> >(tee "$DIR/k6-stderr.log" >&2)
CODE=$?
wait

echo "finished:   $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DIR/run-info.txt"
echo "k6 exit:    $CODE (0 = all thresholds met, 99 = a threshold failed, other = error)" >> "$DIR/run-info.txt"

# k6 exits 0 even if the client slept for an hour mid-run. Check the data itself.
case "$SCENARIO" in e1) PLANNED=180 ;; e2) PLANNED=900 ;; e3) PLANNED=300 ;; e4) PLANNED=270 ;; esac
PLANNED=$(python -I -c "print($PLANNED * float('${TIME_SCALE:-1}'))")
CHECK=$(python -I loadtest/check_run.py "$DIR/$SCENARIO-raw.json.gz" "$PLANNED" 2>&1)
CHECK_CODE=$?
echo "run check:  $CHECK" >> "$DIR/run-info.txt"
if [ "$CHECK_CODE" -ne 0 ]; then
  echo "valid:      NO, do not use this run" >> "$DIR/run-info.txt"
  echo
  echo "!!! RUN INVALID: $CHECK"
  echo "!!! k6 itself exited $CODE. Do not use or commit this run; fix the cause and re-run."
  CODE=97
else
  echo "valid:      yes ($CHECK)" >> "$DIR/run-info.txt"
fi

echo
echo "results saved in $DIR"
echo "next: collect CloudWatch for the window in run-info.txt, then commit results/ as produced."
echo "      run infra/down.sh when you are finished with the stack."
exit $CODE
