"""
Print the E4 per-issuer, per-phase table from a run's e4-summary.json.

Usage: python -I loadtest/digest.py <results dir> [<results dir> ...]
"""
import json
import sys
from pathlib import Path

ISSUERS = ["CBSE", "PARIVAHAN"]
PHASES = ["baseline", "slow", "down", "recovery"]


def metric(data, name):
    return data["metrics"].get(name, {}).get("values", {})


for folder in sys.argv[1:]:
    d = Path(folder)
    data = json.loads((d / "e4-summary.json").read_text())
    info = (d / "run-info.txt").read_text().splitlines()[0]
    print(f"== {info}  ({d.name})")
    print(f"{'issuer':<10} {'phase':<9} {'served':>8} {'n':>5} {'p50 ms':>8} {'p95 ms':>8} {'max ms':>8}")
    for issuer in ISSUERS:
        for phase in PHASES:
            sel = f"{{issuer:{issuer},phase:{phase}}}"
            served = metric(data, "served" + sel)
            dur = metric(data, "http_req_duration" + sel)
            if not served:
                continue
            n = served.get("passes", 0) + served.get("fails", 0)
            print(f"{issuer:<10} {phase:<9} {served['rate'] * 100:>7.1f}% {n:>5} "
                  f"{dur.get('med', 0):>8.0f} {dur.get('p(95)', 0):>8.0f} {dur.get('max', 0):>8.0f}")
    print()
