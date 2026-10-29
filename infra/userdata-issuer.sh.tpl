#!/bin/bash
# Boot script for a mock issuer instance. One issuer per instance, so a
# degraded issuer cannot steal CPU from the healthy one.
set -euxo pipefail

dnf install -y python3.11 python3.11-pip
mkdir -p /opt/issuer && cd /opt/issuer
aws s3 cp s3://__BUCKET__/issuer.tgz . --region __REGION__
tar xzf issuer.tgz
python3.11 -m pip install -r mock-issuer/requirements.txt

cat > /etc/systemd/system/issuer.service <<'UNIT'
[Unit]
Description=Mock issuer
After=network-online.target

[Service]
WorkingDirectory=/opt/issuer/mock-issuer
Environment=ISSUER_ID=__ISSUER_ID__
ExecStart=/usr/bin/python3.11 -m uvicorn main:app --host 0.0.0.0 --port 9000
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now issuer
