import type { MiddlewareHandler } from "hono";
import { errorResponse } from "./responses";
import type { AppEnv, AuthenticatedUser, JwtPayload, UserRole } from "./types";

const JWT_ALGORITHM = { name: "HMAC", hash: "SHA-256" } as const;
const VALID_ROLES = new Set<UserRole>(["ATTENDEE", "STAFF", "SPONSOR", "COMMUNITY"]);

export class AuthError extends Error {}

interface JwtHeader {
  alg: string;
  typ?: string;
}

export async function authenticateJwt(
  authorization: string | null,
  env: AppEnv["Bindings"],
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<AuthenticatedUser> {
  const token = extractBearerToken(authorization);
  if (!token) {
    throw new AuthError("Missing bearer token.");
  }

  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new AuthError("Malformed JWT.");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = parseBase64UrlJson<JwtHeader>(encodedHeader);
  const payload = parseBase64UrlJson<Partial<JwtPayload>>(encodedPayload);

  if (header.alg !== "HS256") {
    throw new AuthError("Unsupported JWT algorithm.");
  }

  await verifySignature(`${encodedHeader}.${encodedPayload}`, encodedSignature, env.JWT_SECRET);
  assertPayload(payload, env, nowSeconds);

  return {
    userId: payload.sub,
    role: payload.role,
    issuer: payload.iss,
    audience: payload.aud,
    expiresAt: payload.exp,
  };
}

export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  try {
    const user = await authenticateJwt(c.req.header("Authorization") ?? null, c.env);
    c.set("authUser", user);
    await next();
  } catch {
    return errorResponse(c, 401, "UNAUTHORIZED", "Missing or invalid JWT.");
  }
};

function extractBearerToken(authorization: string | null) {
  if (!authorization) {
    return null;
  }

  const [scheme, token] = authorization.split(" ");
  if (scheme !== "Bearer" || !token) {
    return null;
  }

  return token;
}

function parseBase64UrlJson<T>(encoded: string): T {
  try {
    const json = new TextDecoder().decode(base64UrlToBytes(encoded));
    return JSON.parse(json) as T;
  } catch {
    throw new AuthError("Invalid JWT JSON.");
  }
}

async function verifySignature(signingInput: string, encodedSignature: string, secret: string) {
  if (!secret) {
    throw new AuthError("Missing JWT secret.");
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    JWT_ALGORITHM,
    false,
    ["sign"],
  );
  const expectedSignature = new Uint8Array(
    await crypto.subtle.sign(JWT_ALGORITHM, key, new TextEncoder().encode(signingInput)),
  );
  const actualSignature = base64UrlToBytes(encodedSignature);

  if (!constantTimeEqual(expectedSignature, actualSignature)) {
    throw new AuthError("Invalid JWT signature.");
  }
}

function assertPayload(
  payload: Partial<JwtPayload>,
  env: AppEnv["Bindings"],
  nowSeconds: number,
): asserts payload is JwtPayload {
  if (
    typeof payload.sub !== "string" ||
    typeof payload.exp !== "number" ||
    typeof payload.iss !== "string" ||
    typeof payload.aud !== "string" ||
    !isUserRole(payload.role)
  ) {
    throw new AuthError("Missing required JWT claims.");
  }

  if (payload.exp <= nowSeconds) {
    throw new AuthError("Expired JWT.");
  }

  if (payload.iss !== env.JWT_ISSUER || payload.aud !== env.JWT_AUDIENCE) {
    throw new AuthError("JWT issuer or audience mismatch.");
  }
}

function isUserRole(value: unknown): value is UserRole {
  return typeof value === "string" && VALID_ROLES.has(value as UserRole);
}

function base64UrlToBytes(encoded: string) {
  const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);

  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }

  return bytes;
}

function constantTimeEqual(expected: Uint8Array, actual: Uint8Array) {
  let diff = expected.length ^ actual.length;
  const length = Math.max(expected.length, actual.length);

  for (let i = 0; i < length; i += 1) {
    diff |= (expected[i] ?? 0) ^ (actual[i] ?? 0);
  }

  return diff === 0;
}
