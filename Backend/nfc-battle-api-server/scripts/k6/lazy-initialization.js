import { check } from "k6";
import crypto from "k6/crypto";
import encoding from "k6/encoding";
import http from "k6/http";

const BASE_URL = (__ENV.BASE_URL || "https://nfc-battle-staging.hitcon2026.online").replace(
  /\/+$/,
  "",
);
const JWT_SECRET = __ENV.JWT_SECRET || "";
const JWT_ISSUER = __ENV.JWT_ISSUER || "";
const JWT_AUDIENCE = __ENV.JWT_AUDIENCE || "";
const USER_PREFIX = __ENV.USER_PREFIX || `k6_lazy_${Date.now()}`;
const RUN_ID = __ENV.RUN_ID || `${Date.now()}`;
const RATE = parsePositiveInteger(__ENV.RATE, 5);
const DURATION = __ENV.DURATION || "30s";

export const options = {
  scenarios: {
    lazy_initialization: {
      executor: "constant-arrival-rate",
      rate: RATE,
      timeUnit: "1s",
      duration: DURATION,
      preAllocatedVUs: parsePositiveInteger(__ENV.PRE_ALLOCATED_VUS, 10),
      maxVUs: parsePositiveInteger(__ENV.MAX_VUS, 50),
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<800", "p(99)<1500"],
    checks: ["rate>0.99"],
  },
};

export function setup() {
  requireEnv("JWT_SECRET", JWT_SECRET);
  requireEnv("JWT_ISSUER", JWT_ISSUER);
  requireEnv("JWT_AUDIENCE", JWT_AUDIENCE);

  return {
    runId: RUN_ID,
    userPrefix: USER_PREFIX,
  };
}

export default function (data) {
  const userId = `${data.userPrefix}_${data.runId}_${__VU}_${__ITER}`;
  const response = http.get(`${BASE_URL}/users/me`, {
    headers: {
      Authorization: `Bearer ${signJwt(userId)}`,
    },
  });

  check(response, {
    "GET /users/me returns 200": (res) => res.status === 200,
    "response belongs to generated user": (res) => {
      const body = res.json();
      return body?.status === "success" && body?.data?.user_id === userId;
    },
  });
}

function signJwt(userId) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = {
    alg: "HS256",
    typ: "JWT",
  };
  const payload = {
    sub: userId,
    exp: nowSeconds + parsePositiveInteger(__ENV.JWT_TTL_SECONDS, 3600),
    iss: JWT_ISSUER,
    aud: JWT_AUDIENCE,
    role: __ENV.USER_ROLE || "ATTENDEE",
  };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = crypto.hmac("sha256", JWT_SECRET, signingInput, "base64rawurl");

  return `${signingInput}.${signature}`;
}

function base64UrlEncode(value) {
  return encoding.b64encode(value, "rawurl");
}

function parsePositiveInteger(value, fallback) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function requireEnv(name, value) {
  if (!value) {
    throw new Error(`${name} is required. Load scripts/k6/.env before running k6.`);
  }
}
