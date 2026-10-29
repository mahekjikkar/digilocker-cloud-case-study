"""
Pointer store. Holds document URIs and metadata, never document files.

Uses DynamoDB when DYNAMODB_TABLE is set, otherwise an in-memory copy of
the same seed data so the service runs locally. Lookups are cached with a
short TTL, which keeps the common path off the database (failure mode F7).
"""
import asyncio
import os
import time

# uri -> (issuer, doc_id, doc_type)
SEED = {
    "CBSE-MARKSHEET-0001": ("CBSE", "0001", "MARKSHEET"),
    "CBSE-MARKSHEET-0002": ("CBSE", "0002", "MARKSHEET"),
    "PARIVAHAN-DL-0001": ("PARIVAHAN", "0001", "DL"),
    "PARIVAHAN-RC-0002": ("PARIVAHAN", "0002", "RC"),
}

TABLE_NAME = os.getenv("DYNAMODB_TABLE")
CACHE_TTL = float(os.getenv("METADATA_CACHE_TTL", "60"))

_table = None
_cache = {}  # uri -> (expires_at, metadata or None)


def _meta(uri, issuer, doc_id, doc_type):
    return {"uri": uri, "issuer": issuer, "doc_id": doc_id, "doc_type": doc_type}


def _get_table():
    global _table
    if _table is None:
        import boto3
        _table = boto3.resource("dynamodb").Table(TABLE_NAME)
    return _table


def _fetch(uri):
    if TABLE_NAME:
        item = _get_table().get_item(Key={"uri": uri}).get("Item")
        if item is None:
            return None
        return _meta(uri, item["issuer"], item["doc_id"], item["doc_type"])
    if uri in SEED:
        return _meta(uri, *SEED[uri])
    return None


def _scan():
    if TABLE_NAME:
        items = _get_table().scan()["Items"]
        return [_meta(i["uri"], i["issuer"], i["doc_id"], i["doc_type"]) for i in items]
    return [_meta(uri, *v) for uri, v in SEED.items()]


async def get_pointer(uri):
    """Return pointer metadata or None. Served from cache when fresh."""
    hit = _cache.get(uri)
    if hit and hit[0] > time.monotonic():
        return hit[1]
    try:
        meta = await asyncio.to_thread(_fetch, uri)
    except Exception:
        # Metadata store trouble: serve a stale entry rather than fail.
        if hit:
            return hit[1]
        raise
    _cache[uri] = (time.monotonic() + CACHE_TTL, meta)
    return meta


async def list_pointers():
    return await asyncio.to_thread(_scan)
