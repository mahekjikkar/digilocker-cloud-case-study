#!/bin/bash
# Boot script for registry instances (launch template user-data).
# Placeholders in __DOUBLE_UNDERSCORES__ are filled in by up.sh.
set -euxo pipefail

dnf install -y python3.11 python3.11-pip
mkdir -p /opt/digilocker && cd /opt/digilocker
aws s3 cp s3://__BUCKET__/app.tgz . --region __REGION__
tar xzf app.tgz
python3.11 -m pip install -r app/requirements.txt

# Rebuilds /etc/digilocker.env from SSM on every service start, so
# set-breaker.sh only has to change the parameter and restart the service.
cat > /usr/local/bin/digilocker-refresh-env <<'SCRIPT'
#!/bin/bash
set -e
export AWS_DEFAULT_REGION=__REGION__
KEY=$(aws ssm get-parameter --name __PARAM_KEY__ --with-decryption --query Parameter.Value --output text)
BRK=$(aws ssm get-parameter --name __PARAM_BREAKER__ --query Parameter.Value --output text)
cat > /etc/digilocker.env <<ENV
API_KEY=$KEY
BREAKER_ENABLED=$BRK
DYNAMODB_TABLE=__TABLE__
AWS_DEFAULT_REGION=__REGION__
CBSE_URL=http://__CBSE_IP__:9000
PARIVAHAN_URL=http://__PARIVAHAN_IP__:9000
ENV
chmod 600 /etc/digilocker.env
SCRIPT
chmod +x /usr/local/bin/digilocker-refresh-env

cat > /etc/systemd/system/digilocker.service <<'UNIT'
[Unit]
Description=DigiLocker registry
After=network-online.target

[Service]
WorkingDirectory=/opt/digilocker/app
ExecStartPre=/usr/local/bin/digilocker-refresh-env
EnvironmentFile=/etc/digilocker.env
ExecStart=/usr/bin/python3.11 -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now digilocker
