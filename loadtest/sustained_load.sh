#!/usr/bin/env bash
# Sustained load against a degraded issuer, sampling a healthy one.
#
# Reproduces failure mode F2: connection pool exhaustion caused by one
# slow issuer degrading access to documents from a healthy issuer.
#
# Run twice with everything else identical: once with the registry
# started normally, once with BREAKER_ENABLED=true.
#
# Usage: ./sustained_load.sh <label>

set -u
LABEL="${1:-unlabelled}"
REGISTRY="localhost:8000"
SLOW_ISSUER="localhost:9001"

LOAD_SECONDS=20
BATCH_SIZE=10
BATCH_INTERVAL=0.5
PROBE_COUNT=20
PROBE_INTERVAL=0.5

echo "# run: $LABEL"
echo "# started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# registry health: $(curl -s $REGISTRY/health)"

curl -s -X POST "$SLOW_ISSUER/control" \
  -H 'Content-Type: application/json' \
  -d '{"down": false, "latency_ms": 3000}' > /dev/null
echo "# CBSE latency set to 3000ms"

( end=$((SECONDS + LOAD_SECONDS))
  while [ $SECONDS -lt $end ]; do
    for i in $(seq 1 $BATCH_SIZE); do
      curl -s -o /dev/null --max-time 15 \
        "$REGISTRY/documents/CBSE-MARKSHEET-0001" &
    done
    sleep $BATCH_INTERVAL
  done ) > /dev/null 2>&1 &

sleep 1
for i in $(seq 1 $PROBE_COUNT); do
  /usr/bin/time -p curl -s -o /dev/null \
    "$REGISTRY/documents/PARIVAHAN-DL-0001" 2>&1 | grep real
  sleep $PROBE_INTERVAL
done

wait
echo "# breaker state: $(curl -s $REGISTRY/breakers)"
echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"