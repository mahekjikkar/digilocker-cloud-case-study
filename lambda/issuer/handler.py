"""
Mock issuer repository, serverless edition.

Stands in for a government department holding documents. Fault state
(latency, outage) lives in DynamoDB rather than memory, because a Lambda
container can be destroyed between invocations.
"""
import json
import os
import time

import boto3

ISSUER_ID = os.environ["ISSUER_ID"]
CONTROL_TABLE = os.environ.get("CONTROL_TABLE", "digilocker-issuer-control")

ddb = boto3.client("dynamodb")

CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Content-Type": "application/json",
}


def reply(status, body):
    return {"statusCode": status, "headers": CORS, "body": json.dumps(body)}


def read_control():
    r = ddb.get_item(
        TableName=CONTROL_TABLE,
        Key={"issuer": {"S": ISSUER_ID}},
    )
    item = r.get("Item", {})
    return {
        "latency_ms": int(item.get("latency_ms", {}).get("N", "20")),
        "down": item.get("down", {}).get("BOOL", False),
    }


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "/")

    if method == "OPTIONS":
        return reply(200, {})

    if path.endswith("/health"):
        return reply(200, {"status": "ok", "issuer": ISSUER_ID})

    if path.endswith("/control") and method == "POST":
        body = json.loads(event.get("body") or "{}")
        expr, names, values = [], {}, {}
        if "latency_ms" in body:
            expr.append("#l = :l")
            names["#l"] = "latency_ms"
            values[":l"] = {"N": str(int(body["latency_ms"]))}
        if "down" in body:
            expr.append("#d = :d")
            names["#d"] = "down"
            values[":d"] = {"BOOL": bool(body["down"])}
        if expr:
            ddb.update_item(
                TableName=CONTROL_TABLE,
                Key={"issuer": {"S": ISSUER_ID}},
                UpdateExpression="SET " + ", ".join(expr),
                ExpressionAttributeNames=names,
                ExpressionAttributeValues=values,
            )
        return reply(200, read_control())

    # /pull/{doc_id}
    state = read_control()
    if state["down"]:
        return reply(503, {"error": "issuer unavailable", "issuer": ISSUER_ID})

    time.sleep(state["latency_ms"] / 1000)

    doc_id = path.rstrip("/").split("/")[-1]
    return reply(200, {
        "issuer": ISSUER_ID,
        "doc_id": doc_id,
        "issued_at": time.time(),
        "signed_xml": f"<Certificate issuer='{ISSUER_ID}' id='{doc_id}'>"
                      f"<Signature>demo</Signature></Certificate>",
    })