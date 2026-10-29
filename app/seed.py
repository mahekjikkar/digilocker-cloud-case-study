"""
Load the pointer table into DynamoDB. Idempotent.

Usage: DYNAMODB_TABLE=digilocker-pointers python seed.py
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
