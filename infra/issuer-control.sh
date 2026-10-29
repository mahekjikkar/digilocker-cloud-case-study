#!/usr/bin/env bash
# Read or change a mock issuer's fault state from your laptop.
# Only your IP (captured when up.sh ran) is allowed through the security group.
# Usage: ./issuer-control.sh CBSE                              show state
#        ./issuer-control.sh CBSE '{"latency_ms":3000}'        slow it down
#        ./issuer-control.sh CBSE '{"down":true}'              total failure
#        ./issuer-control.sh CBSE '{"latency_ms":20,"down":false,"error_rate":0}'   reset
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$STATE_FILE"

case "${1:-}" in
  CBSE)      URL=$CBSE_CONTROL_URL ;;
  PARIVAHAN) URL=$PARIVAHAN_CONTROL_URL ;;
  *) echo "usage: ./issuer-control.sh CBSE|PARIVAHAN ['{json}']"; exit 1 ;;
esac

if [ -n "${2:-}" ]; then
  curl -s -m 10 -X POST "$URL/control" -H 'Content-Type: application/json' -d "$2"
else
  curl -s -m 10 "$URL/control"
fi
echo
