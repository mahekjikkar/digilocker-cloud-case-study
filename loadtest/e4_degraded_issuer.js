// E4: one issuer degraded, then dead. Run twice: breaker off, breaker on.
//
// Expected (Week 2 report, Section 6):
//   without a breaker: both issuers degrade
//   with one: the affected issuer fails fast, the healthy issuer is unaffected
//
// Timeline (seconds): 0-30 baseline | 30-120 CBSE at 3000 ms latency (F2)
//                     120-180 CBSE down (F3) | 180-270 CBSE restored
// CBSE gets steady load, which is what exhausts the registry's connection
// pool when it is slow. PARIVAHAN is healthy throughout and is only probed
// lightly, so its latency and served rate show whether CBSE's trouble leaks.
// Compare issuer:PARIVAHAN,phase:slow between the two runs.
//
// Only the breaker switch (infra/set-breaker.sh) may differ between runs.
import http from 'k6/http';
import { fail } from 'k6';
import {
  BASE_URL, commonOptions, control, elapsedMs, fetchDoc, scaled, secs, summarize, surface,
} from './lib.js';

const CBSE = __ENV.CBSE_CONTROL_URL;
const PARIVAHAN = __ENV.PARIVAHAN_CONTROL_URL;
const HEALTHY = { latency_ms: 20, error_rate: 0, down: false };

const T_SLOW = 30, T_DOWN = 120, T_RESTORE = 180, T_END = 270;
const PHASES = ['baseline', 'slow', 'down', 'recovery'];

export const options = {
  ...commonOptions,
  scenarios: {
    cbse_load: {
      executor: 'constant-arrival-rate', exec: 'cbseLoad',
      rate: 20, timeUnit: '1s', duration: secs(T_END),
      preAllocatedVUs: 150, maxVUs: 400,
    },
    parivahan_probe: {
      executor: 'constant-arrival-rate', exec: 'parivahanProbe',
      rate: 5, timeUnit: '1s', duration: secs(T_END),
      preAllocatedVUs: 30, maxVUs: 150,
    },
    breaker_observer: {
      executor: 'constant-arrival-rate', exec: 'observeBreakers',
      rate: 1, timeUnit: '2s', duration: secs(T_END),
      preAllocatedVUs: 2, maxVUs: 5,
    },
    inject_slow: {
      executor: 'per-vu-iterations', exec: 'injectSlow', vus: 1, iterations: 1,
      startTime: secs(T_SLOW),
    },
    inject_down: {
      executor: 'per-vu-iterations', exec: 'injectDown', vus: 1, iterations: 1,
      startTime: secs(T_DOWN),
    },
    inject_restore: {
      executor: 'per-vu-iterations', exec: 'injectRestore', vus: 1, iterations: 1,
      startTime: secs(T_RESTORE),
    },
  },
  thresholds: surface(
    ['CBSE', 'PARIVAHAN'].flatMap((issuer) => PHASES.map((phase) => ({ issuer, phase }))),
  ),
};

function phase() {
  const t = elapsedMs() / 1000;
  if (t < scaled(T_SLOW)) return 'baseline';
  if (t < scaled(T_DOWN)) return 'slow';
  if (t < scaled(T_RESTORE)) return 'down';
  return 'recovery';
}

export function setup() {
  if (!CBSE || !PARIVAHAN) fail('CBSE_CONTROL_URL and PARIVAHAN_CONTROL_URL must be set');

  // Guard against labelling a run with the wrong breaker mode.
  const health = http.get(`${BASE_URL}/health`).json();
  const mode = health.breaker_enabled ? 'on' : 'off';
  if (__ENV.BREAKER && __ENV.BREAKER !== mode) {
    fail(`run is labelled breaker-${__ENV.BREAKER} but the registry reports breaker ${mode}`);
  }
  console.log(`SETUP breaker=${mode}`);

  // Start from a known-healthy state, and fail now if the issuers are unreachable.
  for (const url of [CBSE, PARIVAHAN]) {
    if (control(url, HEALTHY).status !== 200) fail(`cannot reach issuer control at ${url}`);
  }
}

export function teardown() {
  control(CBSE, HEALTHY);
  control(PARIVAHAN, HEALTHY);
  console.log('TEARDOWN issuers reset to healthy');
}

export function cbseLoad() {
  fetchDoc('CBSE', { phase: phase() });
}

export function parivahanProbe() {
  fetchDoc('PARIVAHAN', { phase: phase() });
}

// Reads one instance's breaker state through the load balancer. Which instance
// answers is not controlled, so treat these as samples. Logged to stderr.
export function observeBreakers() {
  const res = http.get(`${BASE_URL}/breakers`, { headers: { 'X-API-Key': __ENV.API_KEY } });
  console.log(`BREAKERS t=${Math.round(elapsedMs() / 1000)}s ${res.body}`);
}

function inject(label, body) {
  const res = control(CBSE, body);
  console.log(`INJECT t=${Math.round(elapsedMs() / 1000)}s ${label} status=${res.status} ${JSON.stringify(body)}`);
}
export function injectSlow() { inject('CBSE slow', { latency_ms: 3000, down: false }); }
export function injectDown() { inject('CBSE down', { down: true }); }
export function injectRestore() { inject('CBSE restored', HEALTHY); }

export function handleSummary(data) {
  return summarize('e4', data);
}
