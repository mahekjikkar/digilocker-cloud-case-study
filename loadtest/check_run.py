"""
Flag a k6 run that stalled or ran far longer (or shorter) than planned.

k6 exits 0 when its thresholds pass, even if the client machine slept for an
hour mid-run and the data is useless. This reads the raw data points and
checks the run on its own terms:

  - longest silence between consecutive requests (a stall)
  - wall-clock span of the run against the planned duration

Usage: python -I loadtest/check_run.py <raw .json.gz> <planned seconds> [max gap seconds]
Exit:  0 run looks sound, 3 run is invalid (reason printed)
"""
import gzip
import re
import sys
from datetime import datetime

TIME = re.compile(r'"time":"([^"]+)"')
OVERRUN_MARGIN = 120   # setup, teardown and k6's graceful stop


def request_times(path):
    times = []
    with gzip.open(path, "rt") as f:
        for line in f:
            if '"metric":"http_reqs"' not in line:
                continue
            m = TIME.search(line)
            if m:
                times.append(datetime.fromisoformat(m.group(1)).timestamp())
    times.sort()
    return times


def main():
    path = sys.argv[1]
    planned = float(sys.argv[2])
    max_gap = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0

    times = request_times(path)
    if len(times) < 2:
        print("INVALID: fewer than 2 requests recorded")
        return 3

    span = times[-1] - times[0]
    gap = max(b - a for a, b in zip(times, times[1:]))
    print(f"requests {len(times)}, span {span:.0f}s (planned {planned:.0f}s), longest gap {gap:.0f}s")

    reasons = []
    if gap > max_gap:
        reasons.append(f"stalled: {gap:.0f}s with no requests (limit {max_gap:.0f}s); "
                       "the client machine probably slept or lost its network")
    if span > planned + OVERRUN_MARGIN:
        reasons.append(f"ran {span:.0f}s against {planned:.0f}s planned")
    if span < planned * 0.8:
        reasons.append(f"ended early: {span:.0f}s of {planned:.0f}s planned")
    if reasons:
        print("INVALID: " + "; ".join(reasons))
        return 3
    return 0


sys.exit(main())
