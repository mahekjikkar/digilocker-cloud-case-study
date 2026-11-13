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
| 5,437 document types and services (661 Central, 4,776 State) as of 31 Jul 2026 | Week 1, Week 2 s.1-2 | **Read directly** in the PIB (MeitY) release "Government Expands Citizen-Centric Digital Public Service Delivery through UMANG and DigiLocker", posted 12 Aug 2026: <https://www.pib.gov.in/PressReleasePage.aspx?PRID=2298116>. It says "5,437 document types/services [Central Government: 661; State Government: 4,776] are available on DigiLocker platform". Also reported by IBEF: <https://www.ibef.org/news/government-expands-citizen-centric-digital-public-service-delivery-through-umang-and-digilocker>. |
| 2,822 onboarded issuers (replaces 2,347) | Week 1, Week 2 s.1-2 and s.4 ("the other 2,346" becomes "the other 2,821") | **Replaced 2026-11-13.** PIB release of 5 Aug 2026, read directly: <https://www.pib.gov.in/PressReleasePage.aspx?PRID=2294910>: "The platform has over 71.66 crore registered users, with more than 936.03 crore documents issued by 2,822 onboarded issuers." **The release gives no as-of date for this figure**, and the identical sentence is already in the PIB release of 29 Jul 2026 (<https://www.pib.gov.in/PressReleasePage.aspx?PRID=2291148>), so it predates both releases. It is not "as of 31 July 2026": the 31 July figure in the 12 Aug release is 72.43 crore users, not 71.66. Cite it to the release date. The earlier 2,347 came from the MeitY Annual Report 2025-26 per Week 1 (as-of date never confirmed); it is superseded, not shown to be wrong. The Week 1 and Week 2 PDFs still say 2,347 and 2,346. |
| ~~More than 941 crore documents~~ **More than 934 crore documents as of 31 July 2026** | Week 2 s.5 | **Corrected and verified.** 941 crore matches no official figure at any date, so it was wrong, not just old. The PIB factsheet https://pib.gov.in/FactsheetDetails.aspx?Id=150840 ("Empowering Governance through Digital Infrastructure", posted 12 Aug 2026) was **read directly** and says "As of 31 July 2026, the platform has registered over 72 crore users and issued more than 934+ Cr documents." The count depends on date and source (934+ crore end-July 2026; 950+ crore March 2026): see below. |
| Hosting at NIC / MeghRaj data centres in Delhi, Hyderabad, Pune, Bhubaneswar | Week 2 s.2 | **Sourced in part.** NIC's four National Data Centres are named verbatim on <https://nichimachal.nic.in/infrastructure/> and <https://ndcbbsr.nic.in/aboutus>. That DigiLocker itself runs from them is **not** stated by any source I read. |
| 1 GB cap on self-uploaded documents | Week 1, Week 2 s.2 | DLTS / NeGD material |
| CBSE ran several result platforms at once, May 2026 | Week 1, Week 2 s.1 | **Sourced in part.** CBSE declared the Class 12 results on 13 May 2026 and they were offered through several channels (press reports, below). That CBSE did this *deliberately to spread demand* is **UNATTRIBUTED**: no CBSE statement found. |

### Sourcing the three figures (searched and read 2026-11-13)

Only pages I actually opened are quoted. Quotes are verbatim (PDF text extraction can
add stray spaces, which are removed). Pages I could not read are listed at the end; nothing from them is quoted.
PIB pages returned HTTP 403 to my web-fetch tool but open with a plain HTTP request that
follows redirects, which is how the PIB pages below were read.

**1. "More than 941 crore documents" was wrong; replaced by "more than 934 crore documents as
of 31 July 2026".** Official sources give different counts for "documents issued", varying with
date and probably with how they are counted. None is 941. The count is date-dependent: 934+
crore at the end of July 2026, 950+ crore in March 2026:

| Source (publisher, date) | What it says | URL |
|---|---|---|
| **PIB factsheet "Empowering Governance through Digital Infrastructure"** (posted 12 Aug 2026; the figure this report now uses) | "As of 31 July 2026, the platform has registered over 72 crore users and issued more than 934+ Cr documents." (read directly 2026-11-13; the URL redirects to `https://www.pib.gov.in/FactsheetDetails.aspx?Id=150840&reg=48&lang=2`) | https://pib.gov.in/FactsheetDetails.aspx?Id=150840 |
| PIB releases posted 29 Jul 2026 and 5 Aug 2026 (MeitY / Digital India) | "over 71.66 crore registered users, with more than 936.03 crore documents issued by 2,822 onboarded issuers" (read directly). Consistent with "934+", which is a rounded floor | https://www.pib.gov.in/PressReleasePage.aspx?PRID=2291148 and https://www.pib.gov.in/PressReleasePage.aspx?PRID=2294910 |
| DigiLocker homepage (NeGD / MeitY; page labelled "Last Updated: Nov 12, 2026", read 2026-11-13) | "900+ Crore" under "Issued Documents"; "70+ Crore" under "Registered Users" | https://www.digilocker.gov.in/ |
| PIB backgrounder "India's Digital Public Infrastructure" (6 Mar 2026) | "As of 5 March 2026, DigiLocker had 67.63 crore users. By March 2026, over 950 crore documents had been issued through the platform" | https://static.pib.gov.in/WriteReadData/specificdocs/documents/2026/mar/doc202636812701.pdf |
| PIB backgrounder "Infrastructure at the Core of India's Development" (9 Jun 2026) | "DigiLocker, with 68.91 crore+ registered users and more than 967 crore issued digital documents" | https://static.pib.gov.in/WriteReadData/specificdocs/documents/2026/jun/doc2026611890701.pdf |
| NeGD case study "DigiLocker: Citizen's Vault of Trust on Public Cloud of India" (Capacity Building Division, NeGD; PDF created 22 Oct 2025) | "as of August 2025, DigiLocker has issued over 990 crore documents and served more than 57 crore registered users across India (source: DigiLocker Statistics dashboard, August 2025)" | https://negd.gov.in/wp-content/uploads/2025/10/Charru-Malhotra-DIgilocker-the-digital-Vault-of-India.pdf |

The exact-number dashboard (`digilocker.gov.in/statistics`) returned HTTP 403 to my tool and was not read.
**Why the number moves:** it depends on the as-of date and on the source's way of counting. The
end-of-July 2026 count is about 936 crore ("936.03 crore" in the 29 Jul and 5 Aug releases, "934+" in
the 12 Aug factsheet, a rounded floor). Earlier and later counts do not rise steadily: 990+ in
Aug 2025, 950+ in Mar 2026, 967+ in Jun 2026, then about 936 at end-July 2026. That points to
different definitions or a recount, not simple growth, and is why 941 cannot be placed: it equals
none of them.

*Effect on the cost model:* the model now takes 934 crore (`DOCUMENTS` in `cost/model.py`),
and `docs/cost-model.md` and the charts were regenerated from it. The conclusion is not
sensitive to the count: the central-storage ratio is 30.5, 30.8, 30.9, 31.0 and 31.2 times
for 900, 934, 950, 967 and 990 crore documents.

**2. NIC / MeghRaj data centres in Delhi, Hyderabad, Pune and Bhubaneswar: sourced.**

| Source | What it says | URL |
|---|---|---|
| NIC Himachal Pradesh State Centre, Infrastructure page (NIC; "Last Updated: 30.10.2026") | "NIC provides Data Centers Services from National Data Centres at Delhi, Hyderabad, Pune and Bhubaneswar." and "NIC launched National Cloud Services in year 2014 under MeghRaj Government of India Cloud Initiative." | https://nichimachal.nic.in/infrastructure/ |
| NDC Bhubaneswar, "About Us" page (NIC National Data Centre Bhubaneswar; footer "© 2018") | "NIC has set up state-of-the-art National Data Centres at NIC Hqrs, Delhi, Pune , Hyderabad and Bhubaneswar" and "30 small data centres at various state capitals" | https://ndcbbsr.nic.in/aboutus |
| NIC Meghalaya State Centre, Infrastructure page (NIC; "Last Updated: Oct 06, 2026") | the same two sentences, and "NIC has been offering services to the government through its 4 National Data Centres and 30 Mini Data Centres" | https://meg.nic.in/infrastructure/ |
| PIB (MeitY) "India building secure, scalable and AI-ready cloud infrastructure to support digital governance", 12 Dec 2025 (read from NeGD's PDF copy) | "The 'GI Cloud', known as MeghRaj, provides secure, scalable and elastic cloud facilities for delivery of e-Governance services." "National Informatics Centre (NIC) offers the cloud services to various Ministries/Departments. As on date, 2,170 Ministries/Departments have hosted their cloud-based applications on 'MeghRaj'." It **does not name the cities** | https://negd.gov.in/wp-content/uploads/2025/12/Press-Release_Press-Information-Bureau3-3.pdf (PIB page: PRID 2202897) |

Two checks on these pages. NIC's national address <https://www.nic.in/service/data-centre/> redirects to the NIC
homepage (`https://www.nic.gov.in/`) and shows no data-centre text, so it is not cited. NIC Delhi's own "Data Centres" page
(<https://del.nic.in/service/data-centres/>, "Oct 23, 2026") lists only **three** centres
("National Data Centres at NIC Hqrs, Delhi, Pune and Hyderabad"), an older wording, so cite the
two pages that name all four. Limits to state in the report. These pages describe NIC's data
centres in general. **No
source I read says DigiLocker runs from those four sites today.** What the NeGD case study
says about DigiLocker's hosting (same URL as above): "The first version of DigiLocker was
released in 2015 and hosted at the National Informatics Centre (NIC)." and "DigiLocker
operates on a secure, government-managed public cloud infrastructure, aligned with
India's digital governance standards and hosted on ISO 27001 certified data centers
under the aegis of MeitY." So the report may say that NIC runs four National Data
Centres, that DigiLocker's first version was hosted at NIC, and that DigiLocker runs on
government-managed ISO 27001 data centres under MeitY, but should not say it runs on
MeghRaj at those four sites.

**3. CBSE results on several platforms, May 2026: sourced in part.**

| Source | What it says | URL |
|---|---|---|
| Careers360 News (Aatif Ammad, 13 May 2026, 1:30 PM IST) | "marksheets available on DigiLocker, UMANG and SMS services"; CBSE "has declared the Class 12 Results 2026 for all streams including science, arts and commerce today, May 13"; "Students can also check their CBSE Class 12 Results 2026 through SMS if the official websites experience heavy traffic." | https://news.careers360.com/cbse-class-12-result-2026-declared-results-nic-in-digilocker-umang-sms-scorecard-download-steps-pass-percentage-osm |
| Onmanorama (staff, 13 May 2026, 2:16 PM IST) | "The Central Board of Secondary Education (CBSE) on Wednesday declared the results of the Class 12 board examination."; lists results.cbse.nic.in, cbse.gov.in, results.nic.in, results.digilocker.gov.in and umang.gov.in, SMS to 7738299899, and IVRS | https://www.onmanorama.com/news/india/2026/05/13/cbse-class-12-results-declared-check-scores.amp.html |
| India.com (13 May 2026, updated 2:52 PM IST) | CBSE websites named; DigiLocker and UMANG described as "coming soon" at that time, so the app channels went live after the websites. No CBSE quote | https://www.india.com/education/cbse-class-12-result-umang-app-digilocker-sms-class-10-hrd-ministry-dhamendra-pradhan-toppers-list-registration-admit-card-supplementary-exam-8413007/amp/ |

Supported: CBSE declared the Class 12 results on 13 May 2026, and they could be
reached through its websites, DigiLocker, UMANG, SMS and IVRS. "At once" is only roughly
true: the app channels followed the websites by hours. **Unattributed: the claim that
CBSE did this deliberately to spread demand.** No CBSE statement says so. The only
load-related sentence is Careers360's own advice about SMS. An official CBSE notice would
settle it, and none could be read. *Recommended wording:* "CBSE declared the Class 12
results on 13 May 2026, available through its websites, DigiLocker, UMANG, SMS and IVRS
(press reports)", without the stated motive.

**Other figures, verified at the source.** Over 72.43 crore registered users, about 72.86 crore access
transactions over the last three years, and 5,437 document types and services (661 Central, 4,776
State) are in the PIB (MeitY) release posted 12 Aug 2026, read directly:
<https://www.pib.gov.in/PressReleasePage.aspx?PRID=2298116>. IBEF and GKToday report the same numbers
(<https://www.ibef.org/news/government-expands-citizen-centric-digital-public-service-delivery-through-umang-and-digilocker>,
<https://www.gktoday.in/digilocker-crosses-72-crore-users-umang-reaches-11-crore/>). The latest issuer
count, 2,822 onboarded issuers, is also read at the source (see the 2,822 row in part 2).

**Not read, so not cited:** the MeitY Annual Report 2025-26 (its listing page is script-driven and
the report was not reached; it was Week 1's source for the superseded 2,347 issuers),
`www.digilocker.gov.in/statistics` (403), `cbse.gov.in` pages (403),
`cbseresults.nic.in` and `results.cbse.nic.in` (no DNS answer from this machine),
`www.nic.in/service/data-centre/` (redirects to the homepage), Shiksha (403), Oneindia (410), and
the Wayback Machine (not fetchable from this tool). The CBSE and DigiLocker-statistics pages were
not retried with a plain HTTP request.

## 3. Inferred or unknown

- **Architecture A is a reconstruction.** No official deployment diagram exists;
  inferences come from DLTS and the API specifications.
- **DigiLocker's cost is unknown.** No infrastructure cost, instance inventory or
  cost-per-transaction figure is published. The cost section of the final report
  must be labelled a modelled estimate for Architecture B, not DigiLocker's spend.
- **Architecture B is our design**, not a claim about DigiLocker's deployment.
- **The average issued-document size (100 KiB) is an assumption.** No source states it and it
  was not measured. The only size figures found, 1 MB and 10 MB, are third-party statements of
  the limit for files citizens upload themselves; they conflict and are not used. The reasoning
  (one-page signed documents, tens to low hundreds of KiB), the 25 to 500 KiB sensitivity
  (central storage 9.4 to 80.7 times our design) and the break-even size (about 2.4 KiB) are in
  [cost-model.md](cost-model.md), "Why 100 KiB". The Digital Locker Technology Specification, which
  describes the document format, could not be re-read on 2026-11-13 (its host returned 504).

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

### Serverless variant and live demonstration (teammate, 2026-11-08 to 2026-11-11)

Mahek Jikkar added a simplified serverless variant of the registry and issuers (AWS
Lambda, API Gateway, DynamoDB; `lambda/`) and a browser console for it (`web/`, served by
GitHub Pages). It is documented in [live-demo.md](live-demo.md) as the project's live
demonstration. Findings:

- **Verified 2026-11-13:** the console URL serves the committed `web/index.html`, every API
  call the page makes succeeds, the cross-origin headers are present, and both issuers
  were healthy. This was checked with HTTP requests, not in a browser, and the Pages
  source setting could not be read without admin access (inferred from the deployments).
  Full log in `live-demo.md`.
- **Not measured:** no load test or results exist for it. The breaker-off against
  breaker-on comparison is available only from E4 on the EC2 build, because the page has
  no breaker switch.
- **Name clash (2026-11-13):** it shares the AWS account with the EC2 stack and both used
  a DynamoDB table named `digilocker-pointers`, which `down.sh` deletes by name. The EC2
  table is now `digilocker-ec2-pointers`, `infra/config.sh` refuses to run on a name that
  matches a demo resource, and `down.sh` finds instances by exact Name tag.
- **Its design differs** from the EC2 build in the breaker rule, shared breaker state, no
  retries, no API key and open control addresses (table in `live-demo.md`).

## 5. Status of open items

Done in this build:
- AWS runs of E1 to E4 (E4 twice, breaker off then on) with CloudWatch exports and
  the E2 per-instance CPU and credit data, all under `results/aws/`.
- E3 after E2: decided and done on the same stack, after scaling the fleet back to 2
  (see part 4).

Still open, and not part of the build:
- Cost model from measured throughput, plus the object-storage counterfactual
  (Week 2 s.5), and the Week 3 report.
- The three figures were searched on 2026-11-13 and corrected (see "Sourcing the three
  figures"). **941 crore documents is replaced by "more than 934 crore documents as of 31 July
  2026"**, verified in the PIB factsheet <https://pib.gov.in/FactsheetDetails.aspx?Id=150840>. The NIC locations are sourced. The CBSE
  result day is sourced except the claim that it was deliberate to spread demand.
  **2,347 issuers is replaced by 2,822 onboarded issuers** (PIB release of 5 Aug 2026,
  <https://www.pib.gov.in/PressReleasePage.aspx?PRID=2294910>; the release gives no as-of date for it).
- Still open: carry the corrected wording into the final report. The Week 1 and Week 2 PDFs
  still say 941 crore, 2,347 issuers and "the other 2,346" (to become 2,821).

Possible follow-ups, not done: re-run E2 with a non-burstable instance type or
unlimited credits to separate capacity from credit exhaustion; test a hard instance
crash for E3; warm the pointer store at startup.
