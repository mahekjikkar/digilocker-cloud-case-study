"""
DigiLocker registry, serverless edition.

Holds document pointers, never documents. Resolves a URI to its issuer
and fetches the document live. One circuit breaker per issuer, with
state in DynamoDB because Lambda containers do not persist.
"""
import json
import os
import time
import urllib.error
import urllib.request

import boto3

POINTERS = os.environ.get("POINTERS_TABLE", "digilocker-pointers")
BREAKERS = os.environ.get("BREAKERS_TABLE", "digilocker-breakers")
ISSUER_BASE = os.environ["ISSUER_BASE"]          # API Gateway base URL
BREAKER_ENABLED = os.environ.get("BREAKER_ENABLED", "true").lower() == "true"
TIMEOUT = float(os.environ.get("ISSUER_TIMEOUT", "1.0"))
THRESHOLD = int(os.environ.get("BREAKER_THRESHOLD", "3"))
RECOVERY = int(os.environ.get("BREAKER_RECOVERY", "10"))

ddb = boto3.client("dynamodb")

CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Content-Type": "application/json",
}
ISSUER_PATH = {"CBSE": "cbse", "PARIVAHAN": "parivahan"}


def reply(status, body):
    return {"statusCode": status, "headers": CORS, "body": json.dumps(body)}


def get_breaker(issuer):
    r = ddb.get_item(TableName=BREAKERS, Key={"issuer": {"S": issuer}})
    it = r.get("Item", {})
    return {
        "failures": int(it.get("failures", {}).get("N", "0")),
        "state": it.get("state", {}).get("S", "closed"),
        "opened_at": float(it.get("opened_at", {}).get("N", "0")),
    }


def put_breaker(issuer, b):
    ddb.put_item(TableName=BREAKERS, Item={
        "issuer": {"S": issuer},
        "failures": {"N": str(b["failures"])},
        "state": {"S": b["state"]},
        "opened_at": {"N": str(b["opened_at"])},
    })


def allows(b):
    if b["state"] == "closed":
        return True
    if b["state"] == "open":
        return time.time() - b["opened_at"] >= RECOVERY
    return True


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "/")

    if method == "OPTIONS":
        return reply(200, {})

    if path.endswith("/health"):
        return reply(200, {"status": "ok", "breaker_enabled": BREAKER_ENABLED})

    if path.endswith("/breakers"):
        out = []
        for issuer in ISSUER_PATH:
            b = get_breaker(issuer)
            out.append({"issuer": issuer, "state": b["state"],
                        "failures": b["failures"]})
        return reply(200, out)

    if path.endswith("/documents"):
        r = ddb.scan(TableName=POINTERS)
        docs = [{"uri": i["uri"]["S"], "issuer": i["issuer"]["S"],
                 "title": i.get("title", {}).get("S", "")} for i in r["Items"]]
        return reply(200, sorted(docs, key=lambda d: d["uri"]))

    # /documents/{uri}
    uri = path.rstrip("/").split("/")[-1]
    r = ddb.get_item(TableName=POINTERS, Key={"uri": {"S": uri}})
    if "Item" not in r:
        return reply(404, {"error": "unknown URI", "uri": uri})

    issuer = r["Item"]["issuer"]["S"]
    doc_id = r["Item"]["doc_id"]["S"]
    title = r["Item"].get("title", {}).get("S", "")

    b = get_breaker(issuer)
    if BREAKER_ENABLED and not allows(b):
        return reply(200, {"uri": uri, "issuer": issuer, "title": title,
                           "degraded": True,
                           "reason": "issuer temporarily unreachable"})

    url = f"{ISSUER_BASE}/{ISSUER_PATH[issuer]}/pull/{doc_id}"
    started = time.time()
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as resp:
            doc = json.loads(resp.read())
    except Exception as exc:
        b["failures"] += 1
        if b["failures"] >= THRESHOLD:
            b["state"] = "open"
            b["opened_at"] = time.time()
        put_breaker(issuer, b)
        return reply(200, {"uri": uri, "issuer": issuer, "title": title,
                           "degraded": True, "reason": type(exc).__name__,
                           "elapsed_ms": int((time.time() - started) * 1000)})

    if b["failures"] or b["state"] != "closed":
        put_breaker(issuer, {"failures": 0, "state": "closed", "opened_at": 0})

    return reply(200, {"uri": uri, "issuer": issuer, "title": title,
                       "degraded": False, "document": doc,
                       "elapsed_ms": int((time.time() - started) * 1000)})