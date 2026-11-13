"""
Load the pointer table into DynamoDB. Idempotent.

Usage: DYNAMODB_TABLE=digilocker-ec2-pointers python seed.py
(infra/up.sh runs this for you with the table name from infra/config.sh.)
"""
import os

import boto3

from store import SEED

table = boto3.resource("dynamodb").Table(os.environ["DYNAMODB_TABLE"])
with table.batch_writer() as batch:
    for uri, (issuer, doc_id, doc_type) in SEED.items():
        batch.put_item(Item={"uri": uri, "issuer": issuer,
                             "doc_id": doc_id, "doc_type": doc_type})
print(f"seeded {len(SEED)} pointers")
