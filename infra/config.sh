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
TABLE="$PROJECT-pointers"
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
