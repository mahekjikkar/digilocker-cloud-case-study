"""
Registry service: a miniature DigiLocker core.

Holds document URIs (pointers), never documents. On request it
resolves a URI to an issuer and fetches the document live.
"""
import os

import httpx
from fastapi import FastAPI

from breaker import CircuitBreaker

app = FastAPI(title="DigiLocker Registry")

BREAKER_ENABLED = os.getenv("BREAKER_ENABLED", "false").lower() == "true"
ISSUER_TIMEOUT = float(os.getenv("ISSUER_TIMEOUT", "1.0"))

# Where each issuer lives. In AWS these become private IPs.
ISSUERS = {
    "CBSE": "http://127.0.0.1:9001",
    "PARIVAHAN": "http://127.0.0.1:9002",
}

# The pointer table. This is the whole architectural point:
# we store a reference, not a file.
POINTERS = {
    "CBSE-MARKSHEET-0001": ("CBSE", "0001"),
    "CBSE-MARKSHEET-0002": ("CBSE", "0002"),
    "PARIVAHAN-DL-0001": ("PARIVAHAN", "0001"),
    "PARIVAHAN-RC-0002": ("PARIVAHAN", "0002"),
}

breakers = {name: CircuitBreaker(name) for name in ISSUERS}

# A bounded connection pool. This matters: it is what gets
# exhausted when an issuer is slow, which is how one dependency
# takes down the whole service.
limits = httpx.Limits(max_connections=5, max_keepalive_connections=2)
client = httpx.AsyncClient(limits=limits, timeout=ISSUER_TIMEOUT)


@app.on_event("shutdown")
async def shutdown():
    await client.aclose()


@app.get("/health")
async def health():
    return {"status": "ok", "breaker_enabled": BREAKER_ENABLED}


@app.get("/breakers")
async def breaker_status():
    return [b.snapshot() for b in breakers.values()]


@app.get("/documents")
async def list_documents():
    """Metadata only. Served from the pointer table, no issuer call."""
    return [{"uri": uri, "issuer": issuer}
            for uri, (issuer, _) in POINTERS.items()]


@app.get("/documents/{uri}")
async def get_document(uri: str):
    pointer = POINTERS.get(uri)
    if pointer is None:
        return {"error": "unknown URI", "uri": uri}

    issuer_id, doc_id = pointer
    breaker = breakers[issuer_id]

    if BREAKER_ENABLED and not breaker.allows_request():
        # Graceful degradation: metadata still returned, no call made.
        return {
            "uri": uri,
            "issuer": issuer_id,
            "degraded": True,
            "reason": "issuer temporarily unreachable",
        }

    url = f"{ISSUERS[issuer_id]}/pull/{doc_id}"
    try:
        response = await client.get(url)
        response.raise_for_status()
    except Exception as exc:
        breaker.record_failure()
        return {"uri": uri, "issuer": issuer_id,
                "degraded": True, "reason": type(exc).__name__}

    breaker.record_success()
    return {"uri": uri, "issuer": issuer_id,
            "degraded": False, "document": response.json()}