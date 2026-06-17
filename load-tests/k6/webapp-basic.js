import http from 'k6/http';

export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 0 },
  ],
};

const BASE_URL = __ENV.BASE_URL || 'http://<application-endpoint>';

export default function () {
  http.get(BASE_URL);
}