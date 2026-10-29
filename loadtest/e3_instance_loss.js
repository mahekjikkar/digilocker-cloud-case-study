// E3: terminate one registry instance mid-test.
//
// Expected (Week 2 report, Section 6): brief error spike, the load balancer
// drains the unhealthy target, the ASG replaces it.
//
// Steady load throughout. run.sh terminates one instance KILL_AT seconds in
// (infra/terminate-one.sh, timestamp in terminate.log). Requests are tagged
// by phase so the error rate during the gap is reported separately:
//   before: until the kill
//   gap:    the 120 s after it
//   after:  the rest
// Time to full capacity comes from the ASG activity history afterwards.
import { commonOptions, elapsedMs, fetchDoc, randomIssuer, scaled, secs, summarize, surface }
  from './lib.js';

const KILL_AT = parseInt(__ENV.KILL_AT || '90', 10);

export const options = {
  ...commonOptions,
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: 20, timeUnit: '1s', duration: secs(300),
      preAllocatedVUs: 40, maxVUs: 150,
    },
  },
  thresholds: surface([{ phase: 'before' }, { phase: 'gap' }, { phase: 'after' }]),
};

function phase() {
  const t = elapsedMs() / 1000;
  if (t < scaled(KILL_AT)) return 'before';
  if (t < scaled(KILL_AT + 120)) return 'gap';
  return 'after';
}

export default function () {
  fetchDoc(randomIssuer(), { phase: phase() });
}

export function handleSummary(data) {
  return summarize('e3', data);
}
