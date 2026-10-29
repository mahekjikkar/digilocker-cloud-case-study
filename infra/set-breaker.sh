#!/usr/bin/env bash
# Switch the circuit breaker on or off across all registry instances.
# This is the only variable that differs between the two E4 runs.
# Usage: ./set-breaker.sh on|off
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$STATE_FILE"

case "${1:-}" in
  on)  VALUE=true ;;
  off) VALUE=false ;;
  *)   echo "usage: ./set-breaker.sh on|off"; exit 1 ;;
esac

# Instances read this parameter on every service start, so replacements the
# ASG launches later pick up the same setting.
aws ssm put-parameter --name "$PARAM_BREAKER" --type String --value "$VALUE" --overwrite >/dev/null

CMD=$(aws ssm send-command --document-name AWS-RunShellScript \
        --targets Key=tag:Role,Values=app \
        --parameters 'commands=["systemctl restart digilocker"]' \
        --query Command.CommandId --output text)
for _ in $(seq 1 30); do
  PENDING=$(aws ssm list-command-invocations --command-id "$CMD" \
              --query "length(CommandInvocations[?Status=='Pending'||Status=='InProgress'])" --output text)
  [ "$PENDING" = "0" ] && break
  sleep 2
done
aws ssm list-command-invocations --command-id "$CMD" \
  --query 'CommandInvocations[].[InstanceId,Status]' --output text

sleep 5
echo "verifying through the load balancer (10 samples, requests spread across instances):"
for _ in $(seq 1 10); do curl -s -m 5 "$BASE_URL/health"; echo; done | sort | uniq -c
