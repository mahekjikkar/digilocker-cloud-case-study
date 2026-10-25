"""
A minimal circuit breaker, one instance per issuer.

Three states:
  closed    - requests flow normally
  open      - requests fail immediately, no call is made
  half_open - one probe is allowed through to test recovery
"""
import time


class CircuitBreaker:
    def __init__(self, name, failure_threshold=3, recovery_seconds=10):
        self.name = name
        self.failure_threshold = failure_threshold
        self.recovery_seconds = recovery_seconds
        self.failures = 0
        self.state = "closed"
        self.opened_at = 0.0

    def allows_request(self) -> bool:
        if self.state == "closed":
            return True
        if self.state == "open":
            if time.monotonic() - self.opened_at >= self.recovery_seconds:
                self.state = "half_open"
                return True
            return False
        return True  # half_open: let the probe through

    def record_success(self):
        self.failures = 0
        self.state = "closed"

    def record_failure(self):
        self.failures += 1
        if self.failures >= self.failure_threshold:
            self.state = "open"
            self.opened_at = time.monotonic()

    def snapshot(self):
        return {"issuer": self.name, "state": self.state,
                "failures": self.failures}