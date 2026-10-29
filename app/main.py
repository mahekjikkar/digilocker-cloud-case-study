"""
Registry service: a miniature DigiLocker core.

Holds document URIs (pointers), never documents. On request it resolves a
URI to an issuer and fetches the document live. The issuer boundary is
protected per issuer by a short timeout, a bounded retry budget with
jitter, and a circuit breaker. When an issuer is unreachable the citizen
gets cached metadata and a note instead of an error.
"""
import asyncio
import os
import random
import secrets
import time
from collections import deque
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException

import store
from breaker import CircuitBreaker, RetryBudget

# Breaker on/off is the single variable that differs between E4 runs.
BREAKER_ENABLED = os.getenv("BREAKER_ENABLED", "false").lower() == "true"
ISSUER_TIMEOUT = float(os.getenv("ISSUER_TIMEOUT", "1.0"))
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "1"))
RETRY_BASE = float(os.getenv("RETRY_BASE_SECONDS", "0.05"))
RETRY_CAP = float(os.getenv("RETRY_CAP_SECONDS", "0.5"))
POOL_MAX = int(os.getenv("POOL_MAX_CONNECTIONS", "5"))
API_KEY = os.getenv("API_KEY")
if not API_KEY:
    raise RuntimeError("API_KEY must be set")

# Where each issuer lives. In AWS these become private IPs.
ISSUERS = {
    "CBSE": os.getenv("CBSE_URL", "http://127.0.0.1:9001"),
    "PARIVAHAN": os.getenv("PARIVAHAN_URL", "http://127.0.0.1:9002"),
}

breakers = {name: CircuitBreaker(
    name,
    window=int(os.getenv("BREAKER_WINDOW", "10")),
    min_calls=int(os.getenv("BREAKER_MIN_CALLS", "3")),
    error_rate=float(os.getenv("BREAKER_ERROR_RATE", "0.5")),
    recovery_seconds=float(os.getenv("BREAKER_RECOVERY_SECONDS", "10")),
) for name in ISSUERS}
budgets = {name: RetryBudget() for name in ISSUERS}

# Per-issuer counters for /metrics (the E4 measurements).
stats = {name: {"requests": 0, "ok": 0, "failed": 0, "short_circuited": 0,
                "retries": 0, "latency_ms": deque(maxlen=500)}
         for name in ISSUERS}

# One bounded pool shared by all issuers. This is what a slow issuer
# exhausts, and why the breaker has to protect it.
limits = httpx.Limits(max_connections=POOL_MAX, max_keepalive_connections=2)
client = httpx.AsyncClient(limits=limits, timeout=ISSUER_TIMEOUT)


@asynccontextmanager
async def lifespan(_):
    yield
    await client.aclose()


app = FastAPI(title="DigiLocker Registry", lifespan=lifespan)


def require_key(x_api_key: str | None = Header(default=None)):
    if x_api_key is None or not secrets.compare_digest(x_api_key, API_KEY):
        raise HTTPException(status_code=401, detail="invalid or missing API key")


def percentile(samples, p):
    if not samples:
        return None
    ordered = sorted(samples)
    return round(ordered[min(len(ordered) - 1, int(len(ordered) * p))], 1)


@app.get("/health")
async def health():
    # Unauthenticated: used by the load balancer health check.
    return {"status": "ok", "breaker_enabled": BREAKER_ENABLED}


@app.get("/breakers", dependencies=[Depends(require_key)])
async def breaker_status():
    return [{**b.snapshot(), "enforced": BREAKER_ENABLED}
            for b in breakers.values()]


@app.get("/metrics", dependencies=[Depends(require_key)])
async def metrics():
    out = {}
    for name, s in stats.items():
        lat = list(s["latency_ms"])
        out[name] = {
            "requests": s["requests"], "ok": s["ok"], "failed": s["failed"],
            "short_circuited": s["short_circuited"], "retries": s["retries"],
            "latency_p50_ms": percentile(lat, 0.50),
            "latency_p95_ms": percentile(lat, 0.95),
            "breaker": breakers[name].snapshot()["state"],
        }
    return {"breaker_enabled": BREAKER_ENABLED, "issuers": out}


@app.get("/documents", dependencies=[Depends(require_key)])
async def list_documents():
    """Metadata only. Served from the pointer store, no issuer call."""
    return await store.list_pointers()


async def pull_from_issuer(issuer_id, doc_id):
    """
    Fetch one document from one issuer. Returns (document, None) on success
    or (None, reason) when the issuer could not be used.
    """
    breaker, budget, s = breakers[issuer_id], budgets[issuer_id], stats[issuer_id]
    s["requests"] += 1
    budget.deposit()
    url = f"{ISSUERS[issuer_id]}/pull/{doc_id}"
    reason = "unknown"

    for attempt in range(MAX_RETRIES + 1):
        if BREAKER_ENABLED and not breaker.allows_request():
            s["short_circuited"] += 1
            return None, "circuit breaker open"

        started = time.monotonic()
        retryable = True
        try:
            response = await client.get(url)
            response.raise_for_status()
            breaker.record_success()
            s["ok"] += 1
            s["latency_ms"].append((time.monotonic() - started) * 1000)
            return response.json(), None
        except httpx.HTTPStatusError as exc:
            reason = f"issuer returned {exc.response.status_code}"
            retryable = exc.response.status_code >= 500
            failed_call = retryable  # a 4xx means the issuer is alive
        except Exception as exc:
            reason = type(exc).__name__
            failed_call = True
        s["latency_ms"].append((time.monotonic() - started) * 1000)
        if failed_call:
            breaker.record_failure()
        else:
            breaker.record_success()

        if not retryable or attempt == MAX_RETRIES or not budget.try_spend():
            break
        s["retries"] += 1
        # Full jitter: spreads retries so they do not arrive in lockstep.
        await asyncio.sleep(random.uniform(0, min(RETRY_CAP, RETRY_BASE * 2 ** attempt)))

    s["failed"] += 1
    return None, reason


@app.get("/documents/{uri}", dependencies=[Depends(require_key)])
async def get_document(uri: str):
    meta = await store.get_pointer(uri)
    if meta is None:
        raise HTTPException(status_code=404, detail="unknown URI")

    document, reason = await pull_from_issuer(meta["issuer"], meta["doc_id"])
    if document is None:
        # Graceful degradation: cached metadata, never a cached document.
        return {
            **meta,
            "degraded": True,
            "reason": reason,
            "note": f"{meta['issuer']} is temporarily unreachable. "
                    "Your document record is shown; the document itself "
                    "will be available when the issuer recovers.",
        }
    return {**meta, "degraded": False, "document": document}
