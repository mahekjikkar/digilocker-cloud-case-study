"""
Per-issuer resilience primitives: a circuit breaker and a retry budget.

Breaker states:
  closed    - requests flow normally
  open      - requests fail immediately, no call is made
  half_open - exactly one probe is allowed through to test recovery

The breaker opens on error rate over a sliding window of recent calls,
not on a single bad response.
"""
import time
from collections import deque


class CircuitBreaker:
    def __init__(self, name, window=10, min_calls=3, error_rate=0.5,
                 recovery_seconds=10):
        self.name = name
        self.min_calls = min_calls
        self.error_rate = error_rate
        self.recovery_seconds = recovery_seconds
        self.outcomes = deque(maxlen=window)  # True = failure
        self.state = "closed"
        self.opened_at = 0.0
        self.probe_started = None

    def allows_request(self) -> bool:
        now = time.monotonic()
        if self.state == "closed":
            return True
        if self.state == "open":
            if now - self.opened_at < self.recovery_seconds:
                return False
            self.state = "half_open"
            self.probe_started = None
        # half_open: one probe at a time. A probe that never reported back
        # (cancelled request) is abandoned after recovery_seconds.
        if self.probe_started is None or now - self.probe_started >= self.recovery_seconds:
            self.probe_started = now
            return True
        return False

    def record_success(self):
        if self.state == "half_open":
            self.state = "closed"
            self.outcomes.clear()
            self.probe_started = None
            return
        self.outcomes.append(False)

    def record_failure(self):
        if self.state == "half_open":
            self._open()
            return
        self.outcomes.append(True)
        failures = sum(self.outcomes)
        if (len(self.outcomes) >= self.min_calls
                and failures / len(self.outcomes) >= self.error_rate):
            self._open()

    def _open(self):
        self.state = "open"
        self.opened_at = time.monotonic()
        self.probe_started = None
        self.outcomes.clear()

    def snapshot(self):
        failures = sum(self.outcomes)
        return {"issuer": self.name, "state": self.state,
                "window_calls": len(self.outcomes), "window_failures": failures}


class RetryBudget:
    """
    Bounds retries per issuer. Every request earns `ratio` tokens and every
    retry spends one, so retries can never exceed a fixed fraction of
    traffic. Without this, retries multiply load on a failing issuer.
    """

    def __init__(self, ratio=0.2, max_tokens=10.0):
        self.ratio = ratio
        self.max_tokens = max_tokens
        self.tokens = max_tokens

    def deposit(self):
        self.tokens = min(self.max_tokens, self.tokens + self.ratio)

    def try_spend(self) -> bool:
        if self.tokens >= 1.0:
            self.tokens -= 1.0
            return True
        return False
