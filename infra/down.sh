#!/usr/bin/env bash
# Destroy everything up.sh created, so nothing keeps billing between runs.
# The budget is kept unless you pass --budget.
# Usage: ./down.sh [--budget]
set -uo pipefail
source "$(dirname "$0")/config.sh"

say() { echo; echo "==> $*"; }
quiet() { "$@" >/dev/null 2>&1 || true; }

say "Auto Scaling group"
if [ "$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
          --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text)" != "None" ]; then
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --force-delete
  while [ "$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
               --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text)" != "None" ]; do
    echo "waiting for instances to terminate"; sleep 10
  done
fi
quiet aws ec2 delete-launch-template --launch-template-name "$LT_NAME"

say "Load balancer and target group"
LB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
           --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -n "$LB_ARN" ] && [ "$LB_ARN" != "None" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$LB_ARN"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$LB_ARN"
fi
TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
           --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  # The ALB's listener can linger briefly after the ALB reports deleted.
  for _ in $(seq 1 12); do
    aws elbv2 delete-target-group --target-group-arn "$TG_ARN" >/dev/null 2>&1 && break
    sleep 5
  done
fi

say "Mock issuer instances"
IDS=$(aws ec2 describe-instances \
        --filters Name=tag:Project,Values="$PROJECT" Name=instance-state-name,Values=pending,running,stopping,stopped \
        --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$IDS" ]; then
  aws ec2 terminate-instances --instance-ids $IDS >/dev/null
  aws ec2 wait instance-terminated --instance-ids $IDS
fi

say "Security groups (retry: the ALB releases its network interfaces slowly)"
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
for name in "$ISSUER_SG_NAME" "$APP_SG_NAME" "$ALB_SG_NAME"; do
  id=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=group-name,Values="$name" \
         --query 'SecurityGroups[0].GroupId' --output text)
  [ "$id" = "None" ] && continue
  for _ in $(seq 1 30); do
    aws ec2 delete-security-group --group-id "$id" >/dev/null 2>&1 && break
    sleep 10
  done
done

say "IAM, DynamoDB, S3, SSM"
quiet aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"
quiet aws iam delete-instance-profile --instance-profile-name "$PROFILE"
quiet aws iam detach-role-policy --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
quiet aws iam delete-role-policy --role-name "$ROLE" --policy-name "$PROJECT-access"
quiet aws iam delete-role --role-name "$ROLE"
quiet aws dynamodb delete-table --table-name "$TABLE"
quiet aws s3 rb "s3://$BUCKET" --force
quiet aws ssm delete-parameters --names "$PARAM_KEY" "$PARAM_BREAKER"

if [ "${1:-}" = "--budget" ]; then
  quiet aws budgets delete-budget --region us-east-1 --account-id "$ACCOUNT" --budget-name "$BUDGET_NAME"
  echo "budget removed"
fi
rm -f "$STATE_FILE"

say "Leftover check"
LEFT=$(aws ec2 describe-instances \
         --filters Name=tag:Project,Values="$PROJECT" Name=instance-state-name,Values=pending,running,stopping,stopped \
         --query 'length(Reservations[].Instances[])' --output text)
echo "live $PROJECT instances: $LEFT"
echo "load balancers: $(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?LoadBalancerName=='$ALB_NAME'])" --output text 2>/dev/null || echo 0)"
echo "target groups: $(aws elbv2 describe-target-groups --query "length(TargetGroups[?TargetGroupName=='$TG_NAME'])" --output text 2>/dev/null || echo 0)"
echo "tables: $(aws dynamodb list-tables --query "length(TableNames[?@=='$TABLE'])" --output text)"
echo "done"
