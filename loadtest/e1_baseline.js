// E1: baseline, steady low load. Our control case.
//
// Expected (Week 2 report, Section 6): flat latency, no scaling events.
// Target: p95 under 1 s, error rate under 1 percent.
// 5 requests/s is about 150 requests per minute per instance, far below the
// autoscaling target, so no scale-out should happen.
import { commonOptions, fetchDoc, randomIssuer, secs, summarize } from './lib.js';

export const options = {
  ...commonOptions,
  scenarios: {
    baseline: {
      executor: 'constant-arrival-rate',
      rate: 5, timeUnit: '1s', duration: secs(180),
      preAllocatedVUs: 20, maxVUs: 50,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    http_req_failed: ['rate<0.01'],
    served: ['rate>0.99'],
  },
};

export default function () {
  fetchDoc(randomIssuer());
}

export function handleSummary(data) {
  return summarize('e1', data);
}
