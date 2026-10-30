# Research log

Three parts: where the case-study facts come from and how far to trust them; what
is inferred or unknown; and engineering findings made while building. Nothing in
part 3 is a measured result for the report. Those come from the AWS runs, which have
not happened yet.

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

## 5. Open items

- AWS runs of E1 to E4 (E4 twice, breaker off then on) and their CloudWatch exports.
- Cost model from measured throughput, plus the object-storage counterfactual
  (Week 2 s.5).
- Confirm and cite the three unattributed figures in part 2.
- Decide whether E3 should follow E2 on the same instances or a fresh stack. The pool
  fix removes the known cause of carry-over, but fresh is cleaner.
