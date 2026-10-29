#!/usr/bin/env bash
# Create a $5/month budget that emails early warnings. Safe to re-run.
# Usage: ./budget.sh you@example.com
#
# The account is on a credit plan, and AWS budgets net credits off by default,
# which would keep the tracked cost at zero and the alarm silent. Credits are
# excluded here so the budget tracks real usage.
# Budget data lags by up to ~24h: it is a safety net, not a live meter.
# The real control is running ./down.sh after every experiment.
set -euo pipefail
source "$(dirname "$0")/config.sh"

EMAIL="${1:?usage: ./budget.sh you@example.com}"

if aws budgets describe-budget --region us-east-1 --account-id "$ACCOUNT" \
     --budget-name "$BUDGET_NAME" >/dev/null 2>&1; then
  echo "budget $BUDGET_NAME already exists"
  exit 0
fi

cat > .tmp/budget.json <<EOF
{
  "BudgetName": "$BUDGET_NAME",
  "BudgetLimit": {"Amount": "5", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostTypes": {
    "IncludeTax": true, "IncludeSubscription": true, "UseBlended": false,
    "IncludeRefund": false, "IncludeCredit": false, "IncludeUpfront": true,
    "IncludeRecurring": true, "IncludeOtherSubscription": true,
    "IncludeSupport": true, "IncludeDiscount": true, "UseAmortized": false
  }
}
EOF

notification() { # type threshold
cat <<EOF
    {"Notification": {"NotificationType": "$1", "ComparisonOperator": "GREATER_THAN",
                      "Threshold": $2, "ThresholdType": "PERCENTAGE"},
     "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "$EMAIL"}]}
EOF
}
{
  echo "["
  notification ACTUAL 20;    echo ","
  notification ACTUAL 60;    echo ","
  notification ACTUAL 100;   echo ","
  notification FORECASTED 100
  echo "]"
} > .tmp/notifications.json

aws budgets create-budget --region us-east-1 --account-id "$ACCOUNT" \
  --budget file://.tmp/budget.json \
  --notifications-with-subscribers file://.tmp/notifications.json
echo "budget $BUDGET_NAME created: alerts to $EMAIL at \$1, \$3, \$5 actual and \$5 forecast"
