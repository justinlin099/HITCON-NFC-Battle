import { check } from "k6";
import crypto from "k6/crypto";
import encoding from "k6/encoding";
import exec from "k6/execution";
import http from "k6/http";

const BASE_URL = (__ENV.BASE_URL || "https://nfc-battle-staging.hitcon2026.online").replace(
  /\/+$/,
  "",
);
const JWT_SECRET = __ENV.JWT_SECRET || "";
const JWT_ISSUER = __ENV.JWT_ISSUER || "";
const JWT_AUDIENCE = __ENV.JWT_AUDIENCE || "";
const PAIR_USER_PREFIX = __ENV.PAIR_USER_PREFIX || "k6_pair_user";
const PAIR_TAG_PREFIX = __ENV.PAIR_TAG_PREFIX || "04:A7";
const PAIR_RUN_ID = __ENV.PAIR_RUN_ID || `${Date.now()}`;
const PAIR_RATE = parsePositiveInteger(__ENV.PAIR_RATE, 10);
const PAIR_DURATION = __ENV.PAIR_DURATION || "30s";

export const options = {
  scenarios: {
    pair_tags: {
      executor: "constant-arrival-rate",
      rate: PAIR_RATE,
      timeUnit: "1s",
      duration: PAIR_DURATION,
      preAllocatedVUs: parsePositiveInteger(__ENV.PAIR_PRE_ALLOCATED_VUS, 10),
      maxVUs: parsePositiveInteger(__ENV.PAIR_MAX_VUS, 50),
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
    runId: PAIR_RUN_ID,
  };
}

export default function (data) {
  const sequence = exec.scenario.iterationInTest + 1;
  const userId = `${PAIR_USER_PREFIX}_${data.runId}_${sequence}`;
  const physicalId = physicalIdFor(data.runId, sequence);
  const response = http.post(
    `${BASE_URL}/tags/pair`,
    JSON.stringify({
      physical_id: physicalId,
    }),
    {
      headers: {
        Authorization: `Bearer ${signJwt(userId)}`,
        "Content-Type": "application/json",
      },
    },
  );

  check(response, {
    "POST /tags/pair returns 200": (res) => res.status === 200,
    "tag paired successfully": (res) => {
      const body = res.json();
      return body?.status === "success";
    },
  });
}

function signJwt(userId, role) {
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
    role: role ?? __ENV.PAIR_USER_ROLE ?? "ATTENDEE",
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

function physicalIdFor(runId, sequence) {
  const hash = crypto.sha256(`${PAIR_TAG_PREFIX}:${runId}:${sequence}`, "hex");
  const suffix = hash.slice(0, 10).match(/.{1,2}/g).join(":").toUpperCase();
  return `${PAIR_TAG_PREFIX}:${suffix}`;
}

function requireEnv(name, value) {
  if (!value) {
    throw new Error(`${name} is required. Load scripts/k6/.env before running k6.`);
  }
}
