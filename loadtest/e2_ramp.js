// E2: ramp to peak concurrency.
//
// Expected (Week 2 report, Section 6): latency flat, then a knee; new
// instances healthy in 2 to 4 minutes, slower than the arrival rate.
//
// Concurrency steps up in plateaus and latency is recorded per plateau
// (latency_at_<n>_vus), which gives the latency-against-concurrency curve.
// Autoscaling reaction time is read afterwards from the ASG activity history
// and CloudWatch, against the start time recorded in run-info.txt.
// This script sets no failing thresholds: finding where the system bends is
// the point, so it must not stop at the knee.
import exec from 'k6/execution';
import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { commonOptions, fetchDoc, randomIssuer, secs, summarize } from './lib.js';

const LEVELS = [10, 25, 50, 100, 150, 200];

const latencyAt = {};
for (const level of LEVELS) {
  latencyAt[level] = new Trend(`latency_at_${level}_vus`, true);
}

const stages = [];
for (const level of LEVELS) {
  stages.push({ duration: secs(20), target: level });   // ramp up
  stages.push({ duration: secs(100), target: level });  // hold
}
// Keep pushing at peak long enough to see scale-out (2-4 min) complete.
stages.push({ duration: secs(180), target: LEVELS[LEVELS.length - 1] });

export const options = {
  ...commonOptions,
  scenarios: {
    ramp: { executor: 'ramping-vus', startVUs: 1, stages, gracefulRampDown: '10s' },
  },
};

export default function () {
  const res = fetchDoc(randomIssuer());
  const active = exec.instance.vusActive;
  const level = LEVELS.find((l) => active <= l) || LEVELS[LEVELS.length - 1];
  latencyAt[level].add(res.timings.duration);
  sleep(0.1);
}

export function handleSummary(data) {
  return summarize('e2', data);
}
