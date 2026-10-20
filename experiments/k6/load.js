// E3 - sustained load against the instrumented applications.
// Usage: BASE_URL=http://apps-01.lab.example:8080 PATHS=/,/health k6 run load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const PATHS = (__ENV.PATHS || '/').split(',');

export const options = {
  scenarios: {
    steady: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 20 },
        { duration: '10m', target: 20 },
        { duration: '2m', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

export default function () {
  for (const path of PATHS) {
    const res = http.get(`${BASE_URL}${path}`, { tags: { endpoint: path } });
    check(res, { 'status < 500': (r) => r.status < 500 });
  }
  sleep(1);
}
