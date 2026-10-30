#!/usr/bin/env bash
# Build the whole stack in ap-south-1:
#   DynamoDB pointer table, S3 artifact bucket, IAM role, 3 security groups,
#   2 mock-issuer instances, launch template, ALB, and an ASG of t3.micro
#   registry instances across two availability zones.
# Safe to re-run: existing pieces are reused. Tear down with ./down.sh.
set -euo pipefail
source "$(dirname "$0")/config.sh"

say() { echo; echo "==> $*"; }
PYTHON="${PYTHON:-python}"

say "Network (default VPC, zones $AZ_A and $AZ_B)"
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
        --query 'Vpcs[0].VpcId' --output text)
[ "$VPC" != "None" ] || { echo "no default VPC in $REGION"; exit 1; }
subnet_in() {
  aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" Name=default-for-az,Values=true \
    --query "Subnets[?AvailabilityZone=='$1'].SubnetId | [0]" --output text
}
SUBNET_A=$(subnet_in "$AZ_A"); SUBNET_B=$(subnet_in "$AZ_B")
[ "$SUBNET_A" != "None" ] && [ "$SUBNET_B" != "None" ] || { echo "default subnets missing"; exit 1; }
echo "vpc $VPC  subnets $SUBNET_A $SUBNET_B"

ensure_sg() { # name description
  local id
  id=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=group-name,Values="$1" \
         --query 'SecurityGroups[0].GroupId' --output text)
  if [ "$id" = "None" ]; then
    id=$(aws ec2 create-security-group --group-name "$1" --description "$2" --vpc-id "$VPC" \
           --query GroupId --output text)
  fi
  echo "$id"
}
allow() { # group-id port source-flag source-value
  aws ec2 authorize-security-group-ingress --group-id "$1" --protocol tcp --port "$2" "$3" "$4" \
    >/dev/null 2>&1 || true   # already present on re-run
}

say "Security groups"
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')
ALB_SG=$(ensure_sg "$ALB_SG_NAME" "DigiLocker ALB")
APP_SG=$(ensure_sg "$APP_SG_NAME" "DigiLocker registry instances")
ISSUER_SG=$(ensure_sg "$ISSUER_SG_NAME" "DigiLocker mock issuers")
allow "$ALB_SG"    80   --cidr 0.0.0.0/0          # public entry point
allow "$APP_SG"    8000 --source-group "$ALB_SG"  # only the ALB reaches the registry
allow "$ISSUER_SG" 9000 --source-group "$APP_SG"  # only the registry calls issuers
allow "$ISSUER_SG" 9000 --cidr "$MY_IP/32"        # your laptop, to inject faults
echo "alb $ALB_SG  app $APP_SG  issuer $ISSUER_SG  (control access from $MY_IP)"

say "Artifacts bucket and code upload"
if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  aws s3api create-bucket --bucket "$BUCKET" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
fi
(cd "$ROOT" && tar --exclude=__pycache__ -czf "$INFRA_DIR/.tmp/app.tgz" app)
(cd "$ROOT" && tar --exclude=__pycache__ -czf "$INFRA_DIR/.tmp/issuer.tgz" mock-issuer)
aws s3 cp .tmp/app.tgz "s3://$BUCKET/app.tgz" --only-show-errors
aws s3 cp .tmp/issuer.tgz "s3://$BUCKET/issuer.tgz" --only-show-errors

say "DynamoDB pointer table"
if ! aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  aws dynamodb create-table --table-name "$TABLE" \
    --attribute-definitions AttributeName=uri,AttributeType=S \
    --key-schema AttributeName=uri,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
fi
aws dynamodb wait table-exists --table-name "$TABLE"
(cd "$ROOT/app" && DYNAMODB_TABLE="$TABLE" "$PYTHON" seed.py)

say "SSM parameters (API key, breaker switch)"
if aws ssm get-parameter --name "$PARAM_KEY" >/dev/null 2>&1; then
  API_KEY=$(aws ssm get-parameter --name "$PARAM_KEY" --with-decryption \
              --query Parameter.Value --output text)
else
  API_KEY=$(openssl rand -hex 16)
  aws ssm put-parameter --name "$PARAM_KEY" --type SecureString --value "$API_KEY" >/dev/null
fi
aws ssm put-parameter --name "$PARAM_BREAKER" --type String --value false --overwrite >/dev/null
echo "breaker starts disabled; use ./set-breaker.sh on|off"

say "IAM role for instances"
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document '{
    "Version":"2012-10-17","Statement":[{"Effect":"Allow",
    "Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  cat > .tmp/role-policy.json <<EOF
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::$BUCKET/*"},
  {"Effect":"Allow","Action":["dynamodb:GetItem","dynamodb:Scan"],
   "Resource":"arn:aws:dynamodb:$REGION:$ACCOUNT:table/$TABLE"},
  {"Effect":"Allow","Action":"ssm:GetParameter",
   "Resource":"arn:aws:ssm:$REGION:$ACCOUNT:parameter/$PROJECT/*"}]}
EOF
  aws iam put-role-policy --role-name "$ROLE" --policy-name "$PROJECT-access" \
    --policy-document file://.tmp/role-policy.json
  aws iam create-instance-profile --instance-profile-name "$PROFILE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"
  echo "waiting for IAM to propagate"; sleep 15
fi

AMI=$(aws ec2 describe-images --owners amazon \
        --filters "Name=name,Values=al2023-ami-2023.*-kernel-*-x86_64" Name=state,Values=available \
        --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
[ -n "$AMI" ] && [ "$AMI" != "None" ] || { echo "could not find an Amazon Linux 2023 AMI"; exit 1; }

fill() { # template output  (shared substitutions)
  sed -e "s|__BUCKET__|$BUCKET|g" -e "s|__REGION__|$REGION|g" -e "s|__TABLE__|$TABLE|g" \
      -e "s|__PARAM_KEY__|$PARAM_KEY|g" -e "s|__PARAM_BREAKER__|$PARAM_BREAKER|g" \
      -e "s|__CBSE_IP__|${CBSE_PRIVATE_IP:-}|g" -e "s|__PARIVAHAN_IP__|${PARIVAHAN_PRIVATE_IP:-}|g" \
      -e "s|__ISSUER_ID__|${ISSUER_ID:-}|g" "$1" > "$2"
}

launch_issuer() { # issuer-id subnet  -> instance id (reuses a live one)
  local id
  id=$(aws ec2 describe-instances \
         --filters Name=tag:Name,Values="$PROJECT-issuer-$1" Name=instance-state-name,Values=pending,running \
         --query 'Reservations[0].Instances[0].InstanceId' --output text)
  if [ "$id" = "None" ]; then
    ISSUER_ID=$1 fill userdata-issuer.sh.tpl ".tmp/userdata-issuer-$1.sh"
    id=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
           --subnet-id "$2" --security-group-ids "$ISSUER_SG" --associate-public-ip-address \
           --iam-instance-profile Name="$PROFILE" \
           --credit-specification CpuCredits=standard \
           --metadata-options HttpTokens=required \
           --user-data "file://.tmp/userdata-issuer-$1.sh" \
           --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$PROJECT-issuer-$1},{Key=Role,Value=issuer},{Key=Project,Value=$PROJECT}]" \
           --query 'Instances[0].InstanceId' --output text)
  fi
  echo "$id"
}
ip_of() { aws ec2 describe-instances --instance-ids "$1" --query "Reservations[0].Instances[0].$2" --output text; }

say "Mock issuers (one instance each, different zones)"
CBSE_ID=$(launch_issuer CBSE "$SUBNET_A")
PARIVAHAN_ID=$(launch_issuer PARIVAHAN "$SUBNET_B")
aws ec2 wait instance-running --instance-ids "$CBSE_ID" "$PARIVAHAN_ID"
CBSE_PRIVATE_IP=$(ip_of "$CBSE_ID" PrivateIpAddress);  CBSE_PUBLIC_IP=$(ip_of "$CBSE_ID" PublicIpAddress)
PARIVAHAN_PRIVATE_IP=$(ip_of "$PARIVAHAN_ID" PrivateIpAddress); PARIVAHAN_PUBLIC_IP=$(ip_of "$PARIVAHAN_ID" PublicIpAddress)
echo "CBSE $CBSE_PRIVATE_IP / $CBSE_PUBLIC_IP   PARIVAHAN $PARIVAHAN_PRIVATE_IP / $PARIVAHAN_PUBLIC_IP"

say "Launch template (t3.micro, standard credits so CPU surcharges cannot accrue)"
fill userdata-app.sh.tpl .tmp/userdata-app.sh
USERDATA=$(base64 -w0 .tmp/userdata-app.sh)
cat > .tmp/lt.json <<EOF
{"ImageId":"$AMI","InstanceType":"$INSTANCE_TYPE",
 "IamInstanceProfile":{"Name":"$PROFILE"},
 "SecurityGroupIds":["$APP_SG"],
 "CreditSpecification":{"CpuCredits":"standard"},
 "MetadataOptions":{"HttpTokens":"required"},
 "UserData":"$USERDATA",
 "TagSpecifications":[{"ResourceType":"instance","Tags":[
   {"Key":"Name","Value":"$PROJECT-app"},{"Key":"Role","Value":"app"},{"Key":"Project","Value":"$PROJECT"}]}]}
EOF
if aws ec2 describe-launch-templates --launch-template-names "$LT_NAME" >/dev/null 2>&1; then
  aws ec2 create-launch-template-version --launch-template-name "$LT_NAME" \
    --source-version '$Latest' --launch-template-data file://.tmp/lt.json >/dev/null
  aws ec2 modify-launch-template --launch-template-name "$LT_NAME" --default-version '$Latest' >/dev/null
else
  aws ec2 create-launch-template --launch-template-name "$LT_NAME" \
    --launch-template-data file://.tmp/lt.json >/dev/null
fi

say "Load balancer and target group"
TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
           --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  TG_ARN=$(aws elbv2 create-target-group --name "$TG_NAME" --protocol HTTP --port 8000 \
             --vpc-id "$VPC" --health-check-path /health --health-check-interval-seconds 10 \
             --health-check-timeout-seconds 5 --healthy-threshold-count 2 \
             --unhealthy-threshold-count 2 --query 'TargetGroups[0].TargetGroupArn' --output text)
  # Short drain so E3 (terminate an instance) recovers quickly.
  aws elbv2 modify-target-group-attributes --target-group-arn "$TG_ARN" \
    --attributes Key=deregistration_delay.timeout_seconds,Value=30 >/dev/null
fi
LB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
           --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -z "$LB_ARN" ] || [ "$LB_ARN" = "None" ]; then
  LB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" --type application \
             --scheme internet-facing --subnets "$SUBNET_A" "$SUBNET_B" --security-groups "$ALB_SG" \
             --query 'LoadBalancers[0].LoadBalancerArn' --output text)
  aws elbv2 create-listener --load-balancer-arn "$LB_ARN" --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
fi
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$LB_ARN" \
            --query 'LoadBalancers[0].DNSName' --output text)

say "Auto Scaling group ($ASG_MIN-$ASG_MAX instances across $AZ_A and $AZ_B)"
if [ "$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
          --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text)" = "None" ]; then
  aws autoscaling create-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" \
    --launch-template "LaunchTemplateName=$LT_NAME,Version=\$Latest" \
    --min-size "$ASG_MIN" --max-size "$ASG_MAX" --desired-capacity "$ASG_MIN" \
    --vpc-zone-identifier "$SUBNET_A,$SUBNET_B" --target-group-arns "$TG_ARN" \
    --health-check-type ELB --health-check-grace-period 300 \
    --tags "Key=Project,Value=$PROJECT,PropagateAtLaunch=true"
fi
aws autoscaling enable-metrics-collection --auto-scaling-group-name "$ASG_NAME" --granularity 1Minute
# Idempotent, and kept outside the create-only block so a re-run repairs it.
# Needs an active ALB: it is rejected while the ALB is still provisioning.
aws elbv2 wait load-balancer-available --load-balancer-arns "$LB_ARN"
LABEL="${LB_ARN#*:loadbalancer/}/${TG_ARN##*:}"
cat > .tmp/scaling.json <<EOF
{"PredefinedMetricSpecification":{"PredefinedMetricType":"ALBRequestCountPerTarget","ResourceLabel":"$LABEL"},
 "TargetValue":$SCALE_TARGET_REQS}
EOF
aws autoscaling put-scaling-policy --auto-scaling-group-name "$ASG_NAME" \
  --policy-name "$PROJECT-requests-per-target" --policy-type TargetTrackingScaling \
  --estimated-instance-warmup 120 --target-tracking-configuration file://.tmp/scaling.json >/dev/null

cat > "$STATE_FILE" <<EOF
BASE_URL=http://$ALB_DNS
API_KEY=$API_KEY
CBSE_CONTROL_URL=http://$CBSE_PUBLIC_IP:9000
PARIVAHAN_CONTROL_URL=http://$PARIVAHAN_PUBLIC_IP:9000
EOF

say "Waiting for registry targets to pass health checks (first boot takes ~3-5 min)"
HEALTHY=0
for _ in $(seq 1 60); do
  HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
              --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
  echo "healthy targets: $HEALTHY / $ASG_MIN"
  [ "$HEALTHY" -ge "$ASG_MIN" ] && break
  sleep 10
done
if [ "$HEALTHY" -lt "$ASG_MIN" ]; then
  echo "NOT READY: only $HEALTHY of $ASG_MIN registry targets healthy after 10 minutes."
  echo "Check the ASG scaling activities and instance console output before loading."
  exit 1
fi

say "Ready"
echo "base url:  http://$ALB_DNS"
echo "settings written to infra/.state.env (git-ignored; holds the API key)"
echo "try:       curl -H \"X-API-Key: $API_KEY\" http://$ALB_DNS/documents"
echo "REMEMBER:  run ./down.sh when you finish an experiment."
