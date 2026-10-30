#!/usr/bin/env bash
# Re-point the mock issuers' control port at your current public IP.
# up.sh opens port 9000 to the IP you had at that moment; if your network
# changes (new Wi-Fi, laptop wake, VPN), issuer control and E4 stop working.
# Usage: ./allow-my-ip.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"

MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')
SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$ISSUER_SG_NAME" \
       --query 'SecurityGroups[0].GroupId' --output text)
[ "$SG" != "None" ] || { echo "issuer security group not found: is the stack up?"; exit 1; }

# Remove old operator addresses (single-IP /32 rules), keep the registry's rule.
for cidr in $(aws ec2 describe-security-groups --group-ids "$SG" \
                --query 'SecurityGroups[0].IpPermissions[?FromPort==`9000`].IpRanges[].CidrIp' --output text); do
  [ "$cidr" = "$MY_IP/32" ] && continue
  aws ec2 revoke-security-group-ingress --group-id "$SG" --protocol tcp --port 9000 --cidr "$cidr" >/dev/null
  echo "removed $cidr"
done
aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 9000 \
  --cidr "$MY_IP/32" >/dev/null 2>&1 || true
echo "issuer control (port 9000) now allows $MY_IP/32"
