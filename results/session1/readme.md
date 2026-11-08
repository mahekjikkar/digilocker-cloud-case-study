# Session 1: local failure isolation experiment

Date: 25 October 2026
Environment: macOS, single machine, no AWS resources used

## Question

Does one slow issuer degrade access to documents from a healthy
issuer, and does a per-issuer circuit breaker prevent it?

## Parameters

Both runs identical except for BREAKER_ENABLED.

| Parameter | Value |
|---|---|
| Connection pool | 5 |
| Client timeout | 1.0 s |
| Breaker threshold | 3 consecutive failures |
| Breaker recovery interval | 10 s |
| CBSE (degraded) latency | 3000 ms |
| PARIVAHAN (control) latency | 20 ms |
| Load | 10 requests every 0.5 s for 20 s |
| Probes | 20 over 10 s |

Pool size and breaker threshold were reduced from 20 and 5 to make
the effect observable at single-machine scale. Applied to both runs.

## Results

| Condition | Median | Degraded probes | Healthy issuer |
|---|---|---|---|
| Baseline, all healthy | 0.04 s | 0 of 1 | Normal |
| Run A, breaker off | 1.02 s | 13 of 20 | Timed out for 6 s |
| Run B, breaker on | 0.03 s | 1 of 20 | Unaffected |

Breaker state after Run B: CBSE open with 40 failures,
PARIVAHAN closed with 0 failures.

## Findings

1. Failure mode F2 reproduces. A healthy issuer was unreachable for
   six continuous seconds because a different issuer was slow. The
   1.02 s readings equal the client timeout, so those requests failed
   rather than merely ran slowly.

2. The cause is the shared connection pool, not any interaction
   between issuers. PARIVAHAN was never contacted during the failed
   requests.

3. A per-issuer breaker restores isolation. PARIVAHAN recorded zero
   failures under load that had previously caused thirteen timeouts.

4. The elevated first probe in Run B is the window before the breaker
   reached its threshold. The 0.90 s final probe is the half-open
   recovery test after the 10 s interval.

## Method notes

Three load patterns were tried. A single probe after a fixed delay
showed nothing. A one-shot burst of 80 requests with 12 probes gave
identical results in both runs, because in httpx the timeout covers
waiting for a pool slot, so all requests expire at the same instant
the breaker would have opened. Sustained load was required to leave
a measurable window.

## Limitations

Single machine, so inter-component latency is negligible. Twenty
samples shows the effect but does not characterise its distribution.
Parameters are ours, not DigiLocker's; no published figures exist.