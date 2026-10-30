#!/usr/bin/env bash
# Export the raw CloudWatch data and ASG scaling history for one k6 run.
#
# Usage: ./loadtest/collect-cloudwatch.sh results/aws/<run folder>
#
# Run it BEFORE infra/down.sh: the load balancer and ASG, and with them their
# metrics dimensions and scaling history, are deleted by teardown.
#
# The time window comes from run-info.txt in the run folder (2 minutes of
# padding before, 5 after). CloudWatch publishes load balancer metrics with a
# delay of a minute or two, so the script waits until 3 minutes after the run
# finished before querying. If you skip the wait (SKIP_WAIT=1) the last minutes
# will be missing.
#
# Output goes to <run folder>/cloudwatch/, one file per metric, exactly as the
# AWS CLI returned it (1-minute periods). Nothing is filtered or rounded; any
# analysis (reaction time, time to full capacity, cost per 1,000 requests) is
# done later from these files and must cite them.
#
# DRY_RUN=1 prints the window and the commands without calling CloudWatch.
set -euo pipefail

RUN_DIR="${1:?usage: ./loadtest/collect-cloudwatch.sh results/aws/<run folder>}"
[ -f "$RUN_DIR/run-info.txt" ] || { echo "no run-info.txt in $RUN_DIR"; exit 1; }
RUN_DIR="$(cd "$RUN_DIR" && pwd)"   # absolute, because config.sh changes directory

source "$(dirname "$0")/../infra/config.sh"

STARTED=$(awk '/^started:/ {print $2}' "$RUN_DIR/run-info.txt")
FINISHED=$(awk '/^finished:/ {print $2}' "$RUN_DIR/run-info.txt")
[ -n "$STARTED" ] && [ -n "$FINISHED" ] || { echo "run-info.txt has no started/finished time (did the run complete?)"; exit 1; }

iso() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }
WIN_START=$(iso "$STARTED - 2 minutes")
WIN_END=$(iso "$FINISHED + 5 minutes")

echo "run:     $RUN_DIR"
echo "started: $STARTED   finished: $FINISHED"
echo "window:  $WIN_START .. $WIN_END"

READY_AT=$(date -u -d "$FINISHED + 3 minutes" +%s)
NOW=$(date -u +%s)
if [ -z "${SKIP_WAIT:-}" ] && [ -z "${DRY_RUN:-}" ] && [ "$NOW" -lt "$READY_AT" ]; then
  echo "waiting $((READY_AT - NOW))s for CloudWatch to catch up (SKIP_WAIT=1 to skip)"
  sleep $((READY_AT - NOW))
fi

if [ -n "${DRY_RUN:-}" ]; then
  LB="app/$ALB_NAME/<hash>"; TG="targetgroup/$TG_NAME/<hash>"
else
  LB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
             --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
  TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
             --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
  if [ -z "$LB_ARN" ] || [ "$LB_ARN" = "None" ] || [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
    echo "load balancer or target group not found: is the stack still up? (run this before down.sh)"
    exit 1
  fi
  LB="${LB_ARN#*:loadbalancer/}"
  TG="${TG_ARN##*:}"
fi

OUT="$RUN_DIR/cloudwatch"
mkdir -p "$OUT"

# fetch <file> <namespace> <metric> <stat flag> <stat> <dimension>...
fetch() {
  local file=$1 ns=$2 metric=$3 flag=$4 stat=$5; shift 5
  local dims=()
  for d in "$@"; do dims+=("Name=${d%%=*},Value=${d#*=}"); done
  local cmd=(aws cloudwatch get-metric-statistics --namespace "$ns" --metric-name "$metric"
             --dimensions "${dims[@]}" --start-time "$WIN_START" --end-time "$WIN_END"
             --period 60 "$flag" "$stat" --output json)
  if [ -n "${DRY_RUN:-}" ]; then
    echo "[dry run] ${cmd[*]} > $file.json"
  else
    "${cmd[@]}" > "$OUT/$file.json"
    echo "saved $file.json ($(grep -c Timestamp "$OUT/$file.json") datapoints)"
  fi
}

ALB=AWS/ApplicationELB
S=--statistics
# Load balancer: what clients experienced.
fetch alb-request-count            $ALB RequestCount                  $S Sum     LoadBalancer=$LB
fetch alb-target-response-time-avg $ALB TargetResponseTime            $S Average LoadBalancer=$LB
fetch alb-target-response-time-p95 $ALB TargetResponseTime            --extended-statistics p95 LoadBalancer=$LB
fetch alb-target-2xx               $ALB HTTPCode_Target_2XX_Count     $S Sum     LoadBalancer=$LB
fetch alb-target-5xx               $ALB HTTPCode_Target_5XX_Count     $S Sum     LoadBalancer=$LB
fetch alb-elb-5xx                  $ALB HTTPCode_ELB_5XX_Count        $S Sum     LoadBalancer=$LB
fetch alb-active-connections       $ALB ActiveConnectionCount         $S Sum     LoadBalancer=$LB
# Target group: health of the registry fleet (E3 time to full capacity).
fetch tg-healthy-hosts             $ALB HealthyHostCount              $S Minimum LoadBalancer=$LB TargetGroup=$TG
fetch tg-unhealthy-hosts           $ALB UnHealthyHostCount            $S Maximum LoadBalancer=$LB TargetGroup=$TG
fetch tg-requests-per-target       $ALB RequestCountPerTarget         $S Sum     TargetGroup=$TG
# Auto Scaling group: capacity over time (E2 reaction time, E3 recovery).
fetch asg-desired-capacity         AWS/AutoScaling GroupDesiredCapacity   $S Average AutoScalingGroupName=$ASG_NAME
fetch asg-in-service               AWS/AutoScaling GroupInServiceInstances $S Average AutoScalingGroupName=$ASG_NAME
fetch asg-pending                  AWS/AutoScaling GroupPendingInstances  $S Average AutoScalingGroupName=$ASG_NAME
fetch asg-total                    AWS/AutoScaling GroupTotalInstances    $S Average AutoScalingGroupName=$ASG_NAME
# Registry CPU across the fleet.
fetch ec2-cpu-avg                  AWS/EC2 CPUUtilization             $S Average AutoScalingGroupName=$ASG_NAME
fetch ec2-cpu-max                  AWS/EC2 CPUUtilization             $S Maximum AutoScalingGroupName=$ASG_NAME

# Scale-out/in and replacement events with their own timestamps. This is the
# authoritative record of autoscaling reaction time; it disappears with the ASG.
if [ -n "${DRY_RUN:-}" ]; then
  echo "[dry run] aws autoscaling describe-scaling-activities --auto-scaling-group-name $ASG_NAME > asg-scaling-activities.json"
else
  aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" --output json \
    > "$OUT/asg-scaling-activities.json"
  echo "saved asg-scaling-activities.json ($(grep -c ActivityId "$OUT/asg-scaling-activities.json") activities, all history; filter by the window)"
fi

{
  echo "collected:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "window:     $WIN_START .. $WIN_END (period 60s)"
  echo "region:     $REGION"
  echo "load balancer dimension: $LB"
  echo "target group dimension:  $TG"
} > "$OUT/collect-info.txt"
[ -n "${DRY_RUN:-}" ] && rm -f "$OUT/collect-info.txt" && rmdir "$OUT" 2>/dev/null
echo "done. commit $RUN_DIR as produced, then run infra/down.sh."
