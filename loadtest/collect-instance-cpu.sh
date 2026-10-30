#!/usr/bin/env bash
# Export per-instance CPU and CPU-credit data for one run, raw.
#
# Usage: ./loadtest/collect-instance-cpu.sh results/aws/<run folder> <instance-id>[:label] ...
#        ./loadtest/collect-instance-cpu.sh results/aws/20261029T210944Z-e2 \
#            i-0b1e2d0aee35e2523:registry-1b i-0c623b9afc19649ae:issuer-CBSE ...
#
# collect-cloudwatch.sh aggregates CPU across the ASG; it does not collect CPU
# credits (they exist only per instance). This adds them. Needed because
# t3.micro instances run out of credits under sustained load and are then
# capped at the baseline, which explains the E2 result.
#
# Works after the stack is torn down: EC2 metrics stay queryable by instance id
# for a while (basic monitoring keeps 5-minute data for 63 days). Which instances
# were in service during the run comes from the run's asg-scaling-activities.json
# and the issuer instance ids noted at the time. The labels are yours.
#
# Output: <run folder>/cloudwatch/instances/<id>-<metric>.json, exactly as the
# AWS CLI returned it (5-minute periods), plus collect-info.txt.
set -euo pipefail

RUN_DIR="${1:?usage: ./loadtest/collect-instance-cpu.sh <run folder> <instance-id>[:label] ...}"
shift
[ "$#" -ge 1 ] || { echo "give at least one instance id"; exit 1; }
[ -f "$RUN_DIR/run-info.txt" ] || { echo "no run-info.txt in $RUN_DIR"; exit 1; }
RUN_DIR="$(cd "$RUN_DIR" && pwd)"

source "$(dirname "$0")/../infra/config.sh"

STARTED=$(awk '/^started:/ {print $2}' "$RUN_DIR/run-info.txt")
FINISHED=$(awk '/^finished:/ {print $2}' "$RUN_DIR/run-info.txt")
[ -n "$STARTED" ] && [ -n "$FINISHED" ] || { echo "run-info.txt has no started/finished time"; exit 1; }

# 2 minutes before to 5 after (as collect-cloudwatch.sh), widened to whole
# 5-minute periods so the datapoints line up.
S=$(( $(date -u -d "$STARTED - 2 minutes" +%s) / 300 * 300 ))
E=$(( ( $(date -u -d "$FINISHED + 5 minutes" +%s) + 299 ) / 300 * 300 ))
WIN_START=$(date -u -d "@$S" +%Y-%m-%dT%H:%M:%SZ)
WIN_END=$(date -u -d "@$E" +%Y-%m-%dT%H:%M:%SZ)

OUT="$RUN_DIR/cloudwatch/instances"
mkdir -p "$OUT"
echo "run: $RUN_DIR"
echo "window: $WIN_START .. $WIN_END (period 300s)"

fetch() { # id file metric stat
  aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name "$3" \
    --dimensions Name=InstanceId,Value="$1" --start-time "$WIN_START" --end-time "$WIN_END" \
    --period 300 --statistics "$4" --output json > "$OUT/$1-$2.json"
}

{
  echo "collected:  $(date -u +%Y-%m-%dT%H:%M:%SZ)  (after the run; instances may already be terminated)"
  echo "window:     $WIN_START .. $WIN_END (period 300s, basic monitoring)"
  echo "region:     $REGION"
  echo "instances:"
} > "$OUT/collect-info.txt"

for arg in "$@"; do
  id="${arg%%:*}"; label="${arg#*:}"; [ "$label" = "$arg" ] && label="-"
  fetch "$id" cpu-utilization-average CPUUtilization Average
  fetch "$id" cpu-utilization-maximum CPUUtilization Maximum
  fetch "$id" cpu-credit-balance-minimum CPUCreditBalance Minimum
  fetch "$id" cpu-credit-usage-sum CPUCreditUsage Sum
  echo "  $id  $label" >> "$OUT/collect-info.txt"
  echo "saved $id ($label): $(grep -c Timestamp "$OUT/$id-cpu-credit-balance-minimum.json") datapoints per metric"
done
echo "done. commit $OUT as produced."
