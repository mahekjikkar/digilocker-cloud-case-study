#!/usr/bin/env bash
# E3 helper: terminate one in-service registry instance and print timestamps.
# The ASG notices and launches a replacement.
# Usage: ./terminate-one.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"

ID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
       --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId | [0]" \
       --output text)
[ "$ID" != "None" ] || { echo "no in-service instance found"; exit 1; }

echo "terminating $ID at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
aws autoscaling terminate-instance-in-auto-scaling-group --instance-id "$ID" \
  --no-should-decrement-desired-capacity --query Activity.Description --output text
