# DigiLocker: resilience at the issuer boundary

IT457 Cloud Computing, Group 36 (Mahek Jikkar, Shambhavi Singh, Meet Jain).

A case study of India's DigiLocker and a scaled-down build of its core: a
registry that holds **pointers, never documents**, fetches each document live from
an issuer it does not control, and stays usable when one issuer is slow or dead.
The experiment contrasts the same load run **with and without a per-issuer
circuit breaker**.

- Load balancer used for the recorded runs (2026-10-29 UTC):
  `http://digilocker-alb-1092861771.ap-south-1.elb.amazonaws.com`
  *(torn down after the runs to save cost, so the link is dead. A rebuilt stack gets
  a new address: `infra/up.sh` prints it and writes it to `infra/.state.env`.)*
- Region: ap-south-1 (Mumbai). **Multi-zone within one region** (ap-south-1a and
  ap-south-1b). Multi-region is a paper design only; cross-region failover was
  not built or tested.

## Two architectures, kept separate

| | What | Where |
|---|---|---|
| **A** | How DigiLocker works today, reconstructed from published specifications. Descriptive. | Week 2 report, sections 2 and 3 |
| **B** | Our proposed multi-region high-availability design. Prescriptive, our own work, not a claim about DigiLocker's real deployment. | Week 2 report, sections 4 to 6 |

What is built here is a scaled-down slice of B. See `docs/`.

## What is built

| Folder | Contents |
|---|---|
| `app/` | Registry service (FastAPI). API-key auth, DynamoDB pointer store with a TTL cache, per-issuer timeout, bounded retries with jitter, per-issuer circuit breaker, cached-metadata degradation, `/metrics`. |
| `mock-issuer/` | One codebase, run once per issuer (`ISSUER_ID`). `/control` injects latency, error rate or total failure. |
| `infra/` | AWS CLI scripts: ALB, ASG of t3.micro across two zones, DynamoDB, mock issuers, IAM, budget alarm, teardown. |
| `loadtest/` | k6 scenarios E1 to E4, a run wrapper, a CloudWatch collector, and a local smoke test. |
| `results/` | Raw output, committed as produced. |
| `docs/` | Reports, Week 1 summary, research log. |

### How a request flows

```
client -> ALB -> registry (ASG, 2 zones) -> DynamoDB (pointer lookup, cached)
                        |
                        +-> per-issuer: timeout, retry budget + jitter, breaker
                                |-> mock issuer CBSE       (own instance)
                                +-> mock issuer PARIVAHAN  (own instance)
```

`GET /documents/{uri}` always answers 200 for a known URI. If the issuer could
not be used the body has `degraded: true`, the cached metadata and a note, and no
document. **Count a document as served only when `degraded` is false**; the k6
scripts do this (`served` metric).

## Experiments

Expected results were written down before running (Week 2 report, section 6).
Each result records whether the expectation held.

| # | Scenario | Script |
|---|---|---|
| E1 | Baseline, steady 5 req/s | `loadtest/e1_baseline.js` |
| E2 | Ramp to 200 concurrent users | `loadtest/e2_ramp.js` |
| E3 | Terminate one registry instance mid-test | `loadtest/e3_instance_loss.js` |
| E4 | Issuer at 3 s latency, then down. **Run twice: breaker off, then on.** | `loadtest/e4_degraded_issuer.js` |

Only the breaker switch differs between the two E4 runs.

## Running it

### Locally, no AWS (smoke test)

Needs Python 3.11+, k6, and `pip install -r app/requirements.txt -r mock-issuer/requirements.txt`.

```bash
./loadtest/smoke-local.sh          # all four scenarios, durations shrunk
SCENARIOS="e4" ./loadtest/smoke-local.sh
```

Output goes to `loadtest/.smoke/` (git-ignored). It checks the scripts work. It is
not evidence for the report: one laptop runs k6, the registry and both issuers.

### On AWS

Needs the AWS CLI configured for ap-south-1, k6, `openssl`, `curl`, and Python with `boto3`.
The stack costs money while up; tear it down after every session.

```bash
./infra/budget.sh you@example.com     # once: $5 budget with email alerts
./infra/up.sh                          # build the stack (about 5 to 10 minutes)

./loadtest/run.sh e1
./loadtest/run.sh e2
./loadtest/run.sh e3                   # terminates one instance 90 s in
./loadtest/run.sh e4 off               # E4, breaker disabled
./loadtest/run.sh e4 on                # E4, breaker enabled

./loadtest/collect-cloudwatch.sh results/aws/<run folder>   # after EACH run

./infra/down.sh                        # destroy everything
```

- Collect CloudWatch data **before** `down.sh`; the load balancer, ASG and their
  history are deleted with the stack. The collector waits until 3 minutes after the
  run ends so CloudWatch has caught up.
- Restart-sensitive state (the breaker, retry budgets) lives per instance in
  memory. `run.sh e4` restarts the registry through `infra/set-breaker.sh` so each
  E4 run starts clean.
- Helpers: `infra/issuer-control.sh` (set an issuer's latency, errors or
  outage from your laptop), `infra/terminate-one.sh`, `infra/set-breaker.sh on|off`,
  `infra/allow-my-ip.sh` (issuer control is limited to the IP you had when `up.sh` ran;
  run this if your network changes mid-session).
- Keep the laptop awake for the whole run: a sleeping client produces a useless run
  (`run.sh` now detects this and exits 97). `loadtest/collect-instance-cpu.sh` adds
  per-instance CPU and CPU-credit data, which `collect-cloudwatch.sh` does not
  collect; it still works after teardown.

### Cost safety

`infra/budget.sh` creates a $5 monthly budget with email alerts at $1, $3, $5 actual
and $5 forecast. Credits are excluded from what it tracks, otherwise a credit-funded
account would never alert. Budget data lags up to about a day, so it is a safety
net: the real control is `infra/down.sh`, which prints a leftover check.

## Results

Nothing here reports a result that has not been measured.

- `results/session1/`: **local pre-runs** by a teammate (breaker off and on, one
  laptop, no AWS). Kept as they were produced. They predate the connection-pool
  fix described below.
- `results/aws/<time>-<scenario>/`: the real runs of 2026-10-29 (UTC), as produced:
  k6 raw data and summaries, CloudWatch exports, `run-info.txt`. E1, E2, E3 and E4
  (breaker off, breaker on) are all there. E2 also has per-instance CPU and CPU
  credit data in `cloudwatch/instances/`.
- Read `docs/research-log.md` (part 4) before interpreting the runs. It records what
  qualifies them: the E2 collapse beyond 100 VUs coincides with the scale-out
  instances running out of CPU credits, E3's errors came from the replacement's cold
  start and not from the termination, and a stalled run is detected, not trusted.
- Run `./loadtest/run.sh` exit code 97 means the run is invalid; do not use it.

## Differences from the Week 2 plan

Stated so the report does not overclaim.

- **Single region, two zones.** Cross-region failover is a paper design only.
- **Auth is a static API key** (`X-API-Key`), standing in for Meri Pehchaan.
- **Pointer store is DynamoDB**, the managed database for the pointer table.
- **The breaker is per registry instance**, not shared across the fleet.
- **The pool bound is an `asyncio.Semaphore`**, not httpx's own pool limit. httpx's
  pool timeout leaked connections in `CONNECTING` state after an overload and the
  registry never recovered, found by the local smoke test. A local pool timeout
  is also deliberately not counted against an issuer's breaker, and not retried.
- **Mock issuer control endpoints are open** to the operator's IP only
  (security group), not authenticated.
- **k6 runs from the operator's laptop** (outside the VPC, as planned), so about
  one round trip to Mumbai is in every latency figure.
- **Instances use standard CPU credits** (t3.micro) so CPU surcharges cannot accrue;
  sustained load may be throttled once credits run out. Results are reported as observed.
