"""
Mock issuer repository: stands in for a government department
that holds documents. Exposes controls so we can inject the
failure modes identified in the Week 2 report (F2 and F3).
"""
import asyncio
import random
import time

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Mock Issuer")

ISSUER_ID = "PARIVAHAN"

# Fault injection state, changed at runtime via POST /control
state = {
    "latency_ms": 20,     # how long this issuer takes to respond
    "error_rate": 0.0,    # fraction of requests that fail
    "down": False,        # total outage
}


class Control(BaseModel):
    latency_ms: int | None = None
    error_rate: float | None = None
    down: bool | None = None


@app.get("/health")
async def health():
    return {"status": "ok", "issuer": ISSUER_ID}


@app.post("/control")
async def control(c: Control):
    """Change this issuer's behaviour mid-experiment."""
    if c.latency_ms is not None:
        state["latency_ms"] = c.latency_ms
    if c.error_rate is not None:
        state["error_rate"] = c.error_rate
    if c.down is not None:
        state["down"] = c.down
    return state


@app.get("/pull/{doc_id}")
async def pull_document(doc_id: str):
    """
    The Pull Doc interface. DigiLocker calls this when a citizen
    opens an issued document.
    """
    if state["down"]:
        raise HTTPException(status_code=503, detail="issuer unavailable")

    await asyncio.sleep(state["latency_ms"] / 1000)

    if random.random() < state["error_rate"]:
        raise HTTPException(status_code=500, detail="issuer error")

    return {
        "issuer": ISSUER_ID,
        "doc_id": doc_id,
        "issued_at": time.time(),
        "signed_xml": f"<Certificate issuer='{ISSUER_ID}' id='{doc_id}'>"
                      f"<Signature>demo</Signature></Certificate>",
    }