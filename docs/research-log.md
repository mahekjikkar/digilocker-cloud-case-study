# Research log

Where the case-study facts come from and how far to trust them (parts 1 to 3);
engineering findings from building and from the AWS runs (part 4); and what is
still open (part 5). The measured results live in `results/` and are analysed in the
report; this log records provenance and the findings that explain or qualify them.
The local smoke test numbers in part 4 are not results.

## 1. Sources and what each supports

As listed in the Week 2 report (section 9) and the Week 1 summary. Links are in those
PDFs. These were not re-read while building; this table records what the team's
documents say each source is used for.

| Source | Publisher, date | Used for |
|---|---|---|
| Digital Locker Technology Specification v2.3 | NeGD, Mar 2015 | Six roles, federated design, URI scheme, "gateway stores nothing", loose coupling |
| Issuer API Specification v1.13 | NeGD, MeitY, May 2024 | Pull/push issuance paths |
| Requester API Specification v2.1 | NeGD, MeitY, Oct 2016 | Consent before retrieval |
| Authorized Partner API Specification v1.13 | NeGD, MeitY, Feb 2021 | Push issuance by partners |
| DigiLocker Partners Resource Centre | API Setu, NeGD | Current specifications, Meri Pehchaan |
| PIB: UMANG and DigiLocker service delivery | PIB, 12 Aug 2026 | User, document type and transaction figures |
| MeitY Annual Report 2025-26 | MeitY, Apr 2026 | Issuer count, second adoption figure |
| PIB: cloud infrastructure for digital governance | PIB, 2025 | Government cloud hosting |
| DigiLocker: Citizen's Vault of Trust on Public Cloud | NeGD, MeitY, Oct 2025 | Origin, hosting history, issued vs uploaded documents |
| DigiLocker: The Digital Briefcase for India's Authentic E-Documents | NeGD, MeitY, 2025 | Background |

Engineering references for Architecture B (design inputs, **not** evidence about
how DigiLocker is built): AWS Well-Architected Reliability Pillar; AWS disaster
recovery whitepaper (four strategies, basis for warm standby); Amazon Builders'
Library, "Timeouts, retries and backoff with jitter"; Microsoft Azure Architecture
Center, Circuit Breaker pattern.

## 2. Figures: provenance

| Figure | Where it appears | Provenance |
|---|---|---|
| 72.43 crore registered users, as of 31 Jul 2026 | Week 1, Week 2 s.1 | Week 1 attributes current figures to the PIB release of 12 Aug 2026 |
| 5,437 document types and services; 2,347 issuers; 4,776 state-level | Week 1, Week 2 s.1-2 | PIB / MeitY Annual Report per Week 1 |
| About 72.86 crore access transactions over three years, so roughly 7 to 8 requests per second | Week 1 point 1, Week 2 F1 | The rate is derived, not published. Recomputed: 72.86 crore = 728.6 million over 3 x 365 x 86,400 s (94.6 million s) is about 7.7 req/s, if "three years" is exactly three. It is an average and says nothing about peaks. |
| More than 941 crore documents made available | Week 2 s.5 | **Source not named in the report text.** Confirm and cite before the final report. |
| Hosting at NIC / MeghRaj data centres in Delhi, Hyderabad, Pune, Bhubaneswar | Week 2 s.2 | **Source not named in the report text.** Presumably the PIB cloud-infrastructure release. Confirm. |
| 1 GB cap on self-uploaded documents | Week 1, Week 2 s.2 | DLTS / NeGD material |
| CBSE ran several result platforms at once, May 2026 | Week 1, Week 2 s.1 | Press reporting cited by the team; no source listed. Confirm. |

## 3. Inferred or unknown

- **Architecture A is a reconstruction.** No official deployment diagram exists;
  inferences come from DLTS and the API specifications.
- **DigiLocker's cost is unknown.** No infrastructure cost, instance inventory or
  cost-per-transaction figure is published. The cost section of the final report
  must be labelled a modelled estimate for Architecture B, not DigiLocker's spend.
- **Architecture B is our design**, not a claim about DigiLocker's deployment.

## 4. Engineering findings from the build

Observed while building and testing. Dates are when found.

| Date | Finding | Resolution |
|---|---|---|
| 2026-10-29 | The IAM user initially lacked permission for SSM, Budgets and IAM introspection, so infra scripts could not have run. | Administrator access attached by the account owner. |
| 2026-10-29 | AWS budgets net credits off by default. On a credit-funded account the tracked cost stays at zero and the alarm never fires. | `infra/budget.sh` sets `IncludeCredit: false`. Budget data lags about a day, so teardown discipline is the real safeguard. |
| 2026-10-29 | The registry systemd unit failed on first boot: `EnvironmentFile` was read before the step that creates it. Found from instance console output and a journal read over SSM. | `EnvironmentFile=-` (optional), no restart rate limit. |
| 2026-10-29 | Attaching the autoscaling policy failed with "Target Groups may not be valid" while the ALB was still `provisioning`. | `up.sh` waits for the ALB to be available; policy creation is idempotent and re-runnable. |
| 2026-10-29 | `down.sh` could not delete the target group straight after the ALB: its listener lingers briefly. A first teardown also appeared not to have run. | Retry loop; leftover check now includes target groups. |
| 2026-10-29 | A first `up.sh` start failed silently because its log folder did not exist yet. | Create the folder before redirecting. |
| 2026-10-29/30 | On Windows with Git Bash: `/ssm/...` parameter names are mangled by path conversion; console output needs UTF-8; a new k6 install is not on the current shell's PATH. | `MSYS_NO_PATHCONV=1` in `infra/config.sh`; `PYTHONUTF8=1`; the smoke script adds k6 to PATH. |
| 2026-10-30 | **Connection-pool leak in the registry.** After an overload, httpx's pool timeout (equal to the request timeout) cancelled queued requests with half-open connections assigned. httpcore leaked them in `CONNECTING` forever; all 5 slots were lost and the registry returned `PoolTimeout` indefinitely, even with idle healthy issuers. It would have invalidated every AWS run after E2. | The bound is now an `asyncio.Semaphore` with a cancellation-safe timeout; httpx has headroom. Two back-to-back overloads now recover fully. A local pool timeout is no longer counted against an issuer's breaker or retried: a saturated pool says nothing about the issuer. |
| 2026-10-30 | `results/session1/` was produced before that fix. | Kept as a local pre-run, as produced; the runs were short. |

### Local smoke test, 2026-10-30 (not evidence)

Shrunk durations, one Windows laptop running k6, registry and issuers together. It
showed the scripts work and that the breaker contrast is visible: with the breaker
off, the healthy issuer was served 18.5% of the time while the other issuer was slow;
with it on, 93.8%. It also showed the cost of a reactive breaker: about 6% of
healthy-issuer requests failed in the first second before it opened, and the failing
issuer's recovery lags by the breaker's 10 s recovery window. These numbers are
**not** results for the report; they come from the AWS runs.

### AWS runs, 2026-10-29 (UTC), ap-south-1, two zones

| Run | Folder under `results/aws/` | k6 exit | Run check |
|---|---|---|---|
| E1 baseline | `20261029T194652Z-e1` | 0 | Ran before the check existed; verified afterwards: 180 s span, longest gap 1 s (not in its `run-info.txt`) |
| E2 ramp | `20261029T210944Z-e2` | 0 | valid: 901 s of 900 planned, longest gap 7 s |
| E3 instance loss | `20261029T213325Z-e3` | 0 | valid: 300 s, gap 0 s |
| E4, breaker off | `20261029T214542Z-e4-breaker-off` | 0 | valid: 270 s, gap 1 s |
| E4, breaker on | `20261029T215408Z-e4-breaker-on` | 0 | valid: 271 s, gap 1 s |

Two attempts were discarded and their folders deleted: the first E2 (laptop sleep,
finding D) and the first E4 with the breaker off (operator IP had changed, so issuer
control was unreachable and the run aborted before any load).

Findings that explain or qualify the results:

**A. The scale-out instances ran out of CPU credits (E2).** The ASG launched two
instances at 21:15:43, six minutes into E2. In the 21:20 to 21:25 period both had a
CPU credit balance of 0.00 and CPU average and maximum of exactly 10.0%, the t3.micro
baseline cap. The two original instances never fell below about 14.7 credits and were
not capped (13.5% average CPU in the same period). The mock issuers were not the
bottleneck (7 to 10% CPU, balance about 20). Alongside this, from 21:18:44 (the second
minute of the 150 VU stage) the served rate fell from about 100% to about 81%, and
requests per target per minute fell from about 10,300 at 100 VUs to about 4,200 at
200 VUs, with all four instances healthy. *Inference, not measured:* the load balancer kept sending a
share of traffic to the capped instances while closed-loop virtual users waited on
them, lowering total throughput; per-target latency was not collected, so this is not
verified. Consequences for the report: "flat, then a knee" held (flat to 50 VUs, bend
at 100), but the collapse beyond it is a burstable-instance effect, not the
architecture's capacity. Credit balance is not reported for the first period after
launch, so the exact moment the cap began is not evidenced. Data:
`results/aws/20261029T210944Z-e2/cloudwatch/instances/`, collected on 2026-10-30 after
the run by `loadtest/collect-instance-cpu.sh` (the main collector aggregates CPU per
ASG and does not collect credits).

**B. ASG-initiated termination is graceful (E3).** One registry instance was
terminated at 21:34:59 (94 s into the run) through the ASG. The ASG deregisters it
from the load balancer first, and there were **no** failed or degraded requests from
the kill until the 207th second. The replacement launched 5 s after the kill. The
"brief error spike at the kill" in the Week 2 plan did not occur. This tested a
graceful ASG termination only; a hard instance crash was not tested and would be
expected to fail requests until the health checks notice (two checks 10 s apart).

**C. A freshly started registry stalls on its first requests (E3).** The
replacement started its service at 21:36:29 (85 s after launch) and its first
document requests completed together in one burst at 21:36:53. That produced 16 k6
timeouts (10 s) and 30 unserved requests between t+207.7 s and t+210.6 s, 30 of 2,359
requests (1.27%) in the gap phase. The likely cause is lazy DynamoDB client set-up on
first use on a cold t3.micro; only the timing is verified, not the cause. For E4 the
breaker switch restarts the service, so `run.sh` sends 120 warm-up requests before
both E4 runs, identically, and records it in `run-info.txt`. Warming the pointer store
at startup would remove the stall; not done.

**D. k6 exits 0 on a stalled run (stall check added).** The first E2 attempt took 61
minutes, not 15: the laptop entered Windows Modern Standby at 01:24:51 IST and left it
at 02:24:51, so k6 sent traffic for about 90 s, nothing for 3,600 s, then 9 requests
(3 of them timeouts), and still exited 0. `loadtest/check_run.py`, called from `run.sh`, now reads the raw
data points and marks a run invalid (exit 97, collection skipped) if the longest gap
exceeds 30 s or the span is more than 120 s over, or under 80% of, the plan. It was
tested on that stalled run, on E1 and on the smoke runs, and later caught a real
failure: the first E4 attempt (IP changed, k6 exit 107 after 10 s). A keep-awake
process ran during the later runs.

Other facts from the AWS session:

| Finding | Resolution |
|---|---|
| ASG replaced a registry instance three times during startup (19:31, 19:35, 19:39) because instances take 3 to 4 minutes to boot and the health-check grace period was 180 s. These replacements appear in every run's `asg-scaling-activities.json` but belong to none of them. | Grace period raised to 300 s, live and in `up.sh`; `up.sh` now exits with an error instead of printing "Ready" when fewer than 2 targets are healthy. |
| The operator's public IP changed mid-session and the issuer control port (restricted to it) became unreachable. | `infra/allow-my-ip.sh` re-points the rule; E4's `setup()` fails fast on this. |
| After E2 the fleet was at 4 instances. E3 and E4 are defined against 2. | The two throttled scale-out instances were removed (terminated with desired capacity decremented) before E3, leaving one registry instance per zone. |
| CloudWatch retains basic-monitoring EC2 data after instances terminate, so per-instance data could be collected the day after teardown. | Used for finding A. |

## 5. Status of open items

Done in this build:
- AWS runs of E1 to E4 (E4 twice, breaker off then on) with CloudWatch exports and
  the E2 per-instance CPU and credit data, all under `results/aws/`.
- E3 after E2: decided and done on the same stack, after scaling the fleet back to 2
  (see part 4).

Still open, and not part of the build:
- Cost model from measured throughput, plus the object-storage counterfactual
  (Week 2 s.5), and the Week 3 report.
- Confirm and cite the three unattributed figures in part 2.

Possible follow-ups, not done: re-run E2 with a non-burstable instance type or
unlimited credits to separate capacity from credit exhaustion; test a hard instance
crash for E3; warm the pointer store at startup.
