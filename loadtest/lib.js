// Shared helpers for the E1-E4 scenarios.
//
// Settings come from the environment (loadtest/run.sh sets them from
// infra/.state.env): BASE_URL, API_KEY, CBSE_CONTROL_URL, PARIVAHAN_CONTROL_URL.
import http from 'k6/http';
import exec from 'k6/execution';
import { Rate } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

export const BASE_URL = __ENV.BASE_URL;
const HEADERS = { 'X-API-Key': __ENV.API_KEY };

// Shrinks every duration for local smoke tests. Leave unset for real runs.
const TIME_SCALE = parseFloat(__ENV.TIME_SCALE || '1');
export const scaled = (seconds) => Math.max(1, Math.round(seconds * TIME_SCALE));
export const secs = (seconds) => `${scaled(seconds)}s`;

const DOCS = {
  CBSE: ['CBSE-MARKSHEET-0001', 'CBSE-MARKSHEET-0002'],
  PARIVAHAN: ['PARIVAHAN-DL-0001', 'PARIVAHAN-RC-0002'],
};

// The registry answers 200 even when the issuer is unreachable, with
// degraded:true. "served" is true only when the real document came back, so
// a status-code check alone would hide exactly the failure E4 measures.
export const served = new Rate('served');

export const commonOptions = {
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  tags: { run: __ENV.RUN_LABEL || 'unlabelled' },
};

export function fetchDoc(issuer, tags = {}) {
  const uris = DOCS[issuer];
  const uri = uris[Math.floor(Math.random() * uris.length)];
  const allTags = { issuer, ...tags };
  const res = http.get(`${BASE_URL}/documents/${uri}`, {
    headers: HEADERS, tags: allTags, timeout: '10s',
  });
  let degraded = true;
  if (res.status === 200) {
    try { degraded = res.json('degraded') !== false; } catch (e) { /* not JSON */ }
  }
  served.add(res.status === 200 && !degraded, allTags);
  return res;
}

export const randomIssuer = () => (Math.random() < 0.5 ? 'CBSE' : 'PARIVAHAN');

// Milliseconds since the test run started.
export const elapsedMs = () => exec.instance.currentTestRunDuration;

// k6 only reports a tagged sub-metric in the summary if a threshold names it.
// These always-true thresholds exist purely to make them appear.
export function surface(tagSets) {
  const thresholds = {};
  for (const ts of tagSets) {
    const sel = Object.entries(ts).map(([k, v]) => `${k}:${v}`).join(',');
    thresholds[`http_req_duration{${sel}}`] = ['max>=0'];
    thresholds[`http_req_failed{${sel}}`] = ['rate>=0'];
    thresholds[`served{${sel}}`] = ['rate>=0'];
  }
  return thresholds;
}

export function control(baseUrl, body) {
  return http.post(`${baseUrl}/control`, JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json' }, timeout: '10s',
  });
}

export function summarize(name, data) {
  const dir = __ENV.RESULTS_DIR || '.';
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: false }),
    [`${dir}/${name}-summary.json`]: JSON.stringify(data, null, 2),
  };
}
