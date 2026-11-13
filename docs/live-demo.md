# Live demonstration: the serverless variant

The live demonstration is a **simplified serverless variant of the EC2 design** that the
experiments measured. It was built by Mahek Jikkar (commits of 8 to 11 November 2026) so
that the central idea can be shown in a browser: a registry that stores a pointer to each
document, fetches it live from the issuing department, and keeps one circuit breaker per
issuer, so that one department can be taken offline while the other keeps working.

It is **not** what experiments E1 to E4 measured. Those ran on the EC2 build (`app/`,
`infra/`, results in `results/aws/`). Nothing has been measured on the serverless variant.

## Where it lives

| | |
|---|---|
| Console (the live URL) | <https://mahekjikkar.github.io/digilocker-cloud-case-study/web/> |
| API base | `https://407xctwyx6.execute-api.ap-south-1.amazonaws.com` |
| API routes | `/api/health`, `/api/breakers`, `/api/documents`, `/api/documents/{uri}`, and `/cbse/...`, `/parivahan/...` for the two fake issuers (`health`, `pull/{id}`, `control`) |
| Source | `lambda/registry/handler.py`, `lambda/issuer/handler.py`, `web/index.html`; the API address is recorded in `lambda/endpoints.txt` |
| AWS resources | Lambda functions `digilocker-registry`, `digilocker-issuer-cbse`, `digilocker-issuer-parivahan`; one API Gateway API named `digilocker`; DynamoDB tables `digilocker-pointers`, `digilocker-breakers`, `digilocker-issuer-control`; IAM role `digilocker-lambda-role`; region ap-south-1 |
| Hosting of the console | GitHub Pages, from the `master` branch of `mahekjikkar/digilocker-cloud-case-study` (the site root also shows the repository README) |

## How it relates to the EC2 design

Each row below comes from the code in the repository.

| | EC2 build (measured) | Serverless variant (live demo) |
|---|---|---|
| Where it runs | FastAPI on t3.micro servers in an Auto Scaling group across two zones, behind a load balancer | Each call is a Lambda invocation behind API Gateway |
| Pointer store | DynamoDB, with a 60 s cache in each server | DynamoDB, read on every call |
| Breaker rule | Opens when at least half of the last 10 calls failed (at least 3 calls); then one test call at a time | Opens after 3 failures in a row; after 10 s calls are allowed again, for every caller |
| Breaker state | In each server's memory, so each server has its own | Shared, stored in DynamoDB (read then write, not atomic) |
| Timeout | 1 s per issuer call | 1 s per issuer call |
| Retries | One retry with a random delay, inside a retry budget | None |
| When an issuer cannot be used | Returns the cached record and a "temporarily unreachable" note | Returns the record's title from the database and the note |
| Connections to issuers | One bounded pool shared by all issuers (what a slow issuer exhausts in E4) | A new connection per call; no shared pool |
| Login | API key required | None |
| Controlling the fake issuers | Restricted by the security group to the operator's IP | Open to anyone with the URL |
| Metrics | `/metrics` per issuer | `/api/breakers` only |
| Evidence | E1 to E4 on AWS, raw data in `results/aws/` | None |

The "new connection per call" row is a reading of the code, not a measurement. It means
the particular effect measured in E4 (a slow issuer using up a shared pool) is not the
mechanism the serverless variant would show; the demo shows the breaker's visible
behaviour, not that effect.

## Verification log

Checked on **2026-11-13, starting 07:01 UTC**, from the same laptop used for the AWS runs.
All requests were reads, except the console's own empty-body `POST {}` to each issuer's
`/control`, which reads the current settings and changes nothing (the console sends it on
every page load).

| Check | Result |
|---|---|
| GitHub reports Pages enabled | `has_pages: true` (public API) |
| Pages deployments | GitHub Pages deployments exist for `master`: 06:42:36Z for commit `e653e7d`, and 06:47:45Z for `287477b`, which was `master`'s latest commit |
| Console URL | HTTP 200 at `.../web/` and `.../web/index.html`, 14,232 bytes |
| Served page against the repository | Identical to `web/index.html` as committed (SHA-256 starts `70791b81`). A local Windows checkout differs only by line endings (335 extra bytes, one per line) |
| API address inside the page | The same as in `lambda/endpoints.txt` |
| `GET /api/health` | 200: `{"status": "ok", "breaker_enabled": true}` |
| `GET /api/breakers` | 200: CBSE and PARIVAHAN both `closed`, 0 failures |
| `GET /cbse/health`, `/parivahan/health` | 200 for both |
| `GET /api/documents` | 200: four documents (two CBSE marksheets, a driving licence, a vehicle registration) |
| `GET /api/documents/CBSE-MARKSHEET-0001` and `PARIVAHAN-DL-0001` | 200, `degraded: false`, signed-XML-shaped document returned |
| `GET /api/documents/NOPE` | 404 `unknown URI` |
| Cross-origin check from the Pages origin | Preflight `OPTIONS` for a `POST` with `content-type` allowed; responses carry `access-control-allow-origin: *` |
| Issuers' settings | Both `{"latency_ms": 20, "down": false}`, i.e. healthy |
| Response time from the laptop | 0.4 to 0.9 s on the first calls, then 0.25 to 0.39 s for five repeated document fetches. Two sampled document fetches reported 172 ms and 285 ms inside the registry |

Two things to note from the log:

- One early request to `.../web/` returned 4,134 bytes instead of the full page. The next
  request, and every one after, returned the full 14,232 bytes. The cause was not
  established and it did not recur.
- The console says opening the driving licence is "usually under 100 ms". The two samples
  above were 172 ms and 285 ms inside the registry, so do not promise a figure at the
  viva; say it is fast.

**Not checked:**
- The console was **not opened in a browser**. Every request the page makes was tested, and
  the cross-origin headers a browser needs are present, but rendering and the buttons were
  not exercised.
- The Pages source setting (branch and folder). Reading it needs repository admin access
  (the API returned 404 without it). It is inferred from the deployments above.
- Behaviour under load, and whether it stays up beyond the time of the check.

## What has to stay in place for the viva

- The repository `mahekjikkar/digilocker-cloud-case-study` stays public with Pages enabled
  on `master`. The live URL is under that GitHub account.
- The Lambda functions, the API Gateway API and the three DynamoDB tables stay deployed in
  the project's AWS account. The EC2 teardown script does not remove them and refuses to
  run if a name in its configuration matches one of theirs.
- Internet access in the room. The page also loads two fonts from Google; without them it
  falls back to default fonts.
- Before presenting: open the console once a minute or two earlier (the first calls are
  slower), and set both issuers to **Healthy**. The controls are open and their settings
  persist, so anyone who used the page last may have left an issuer slow or offline.
- A change pushed to `master` can take a few minutes to appear. The page is served with a
  10-minute cache lifetime.

## If it stops working

1. **The console URL returns 404.** In the repository's Settings, Pages: the source should
   be "Deploy from a branch", branch `master`, folder `/ (root)`. The console is then at
   `/web/`. If the source is `/docs` instead, `web/` would have to move there. The latest
   "pages build and deployment" run is under the repository's Actions tab.
2. **The page loads but shows that the API cannot be reached.** Check the API address with
   the commands below. If it fails, check the API Gateway API `digilocker` and the three
   Lambda functions in the AWS console, that the registry function's `ISSUER_BASE`
   environment variable equals the API base, and that the three DynamoDB tables exist.
3. **An issuer looks broken.** Set it back to Healthy on the page, or `POST` the body
   `{"down": false, "latency_ms": 20}` to `/{cbse|parivahan}/control`.

## Re-checking it yourself

```bash
B=https://407xctwyx6.execute-api.ap-south-1.amazonaws.com
curl -s $B/api/health
curl -s $B/api/breakers
curl -s $B/api/documents
curl -s $B/api/documents/CBSE-MARKSHEET-0001
curl -s -o /dev/null -w "%{http_code}\n" https://mahekjikkar.github.io/digilocker-cloud-case-study/web/
# Read an issuer's current settings (empty body: changes nothing; the console does the same):
curl -s -X POST -H "Content-Type: application/json" -d '{}' $B/cbse/control
```

Do not send a non-empty body to `/control` unless you mean to change an issuer.

## Limits to state when presenting it

- It has no measurements and was not load tested.
- It has no API key, and the control addresses for the fake issuers are open to anyone
  who has the URL.
- It cannot show the breaker off against on: the page offers only Healthy, Slow and
  Offline, and the API reports the breaker enabled. That comparison is experiment E4 on the
  EC2 build.
- It uses the same four fake documents as the EC2 build and fake issuers throughout.
- It shares an AWS account with the EC2 stack, which once caused a name clash on a database
  table (resolved by renaming the EC2 table).
