#!/usr/bin/env bash
# Shared settings, sourced by every script in this folder.
# Everything is deployed to ap-south-1 (Mumbai), the report's primary region.

export MSYS_NO_PATHCONV=1          # stop Git Bash rewriting /ssm/style/paths
export AWS_PAGER=""
export AWS_DEFAULT_REGION=ap-south-1
REGION=ap-south-1

PROJECT=digilocker
INSTANCE_TYPE=t3.micro
AZ_A=ap-south-1a
AZ_B=ap-south-1b

# Autoscaling. Target is ALB requests per target per minute: the report scales
# the stateless tier on request count.
ASG_MIN=2
ASG_MAX=4
SCALE_TARGET_REQS="${SCALE_TARGET_REQS:-1000}"

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$INFRA_DIR/.." && pwd)"
cd "$INFRA_DIR"                    # relative file:// paths below depend on this
mkdir -p .tmp
STATE_FILE="$INFRA_DIR/.state.env"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text) || exit 1
if [ "$(aws configure get region 2>/dev/null)" != "$REGION" ]; then
  echo "note: CLI default region is not $REGION; forcing $REGION for this run"
fi

BUCKET="$PROJECT-artifacts-$ACCOUNT"
# Not "$PROJECT-pointers": the serverless demo (lambda/) in the same account uses that name,
# and down.sh deletes this table by name.
TABLE="$PROJECT-ec2-pointers"
ROLE="$PROJECT-instance-role"
PROFILE="$PROJECT-instance-profile"
ALB_SG_NAME="$PROJECT-alb-sg"
APP_SG_NAME="$PROJECT-app-sg"
ISSUER_SG_NAME="$PROJECT-issuer-sg"
LT_NAME="$PROJECT-app-lt"
TG_NAME="$PROJECT-app-tg"
ALB_NAME="$PROJECT-alb"
ASG_NAME="$PROJECT-app-asg"
PARAM_KEY="/$PROJECT/api_key"
PARAM_BREAKER="/$PROJECT/breaker_enabled"
BUDGET_NAME="$PROJECT-5usd"
# Exact Name tags of the instances this stack launches (see the tags in up.sh).
OUR_INSTANCE_NAMES="$PROJECT-app,$PROJECT-issuer-CBSE,$PROJECT-issuer-PARIVAHAN"

# The serverless demo (lambda/, web/) lives in the same AWS account. Refuse to run if any
# name above matches one of its resources, so up.sh can never write to them and down.sh
# can never delete them. Add to this list if the demo gains resources.
DEMO_RESOURCE_NAMES=" digilocker-pointers digilocker-breakers digilocker-issuer-control \
digilocker-lambda-role digilocker-registry digilocker-issuer-cbse digilocker-issuer-parivahan "
for name in "$BUCKET" "$TABLE" "$ROLE" "$PROFILE" "$ALB_SG_NAME" "$APP_SG_NAME" "$ISSUER_SG_NAME" \
            "$LT_NAME" "$TG_NAME" "$ALB_NAME" "$ASG_NAME" "$PARAM_KEY" "$PARAM_BREAKER" "$BUDGET_NAME"; do
  case "$DEMO_RESOURCE_NAMES" in
    *" $name "*) echo "refusing to run: '$name' is a serverless-demo resource name"; exit 1 ;;
  esac
done
