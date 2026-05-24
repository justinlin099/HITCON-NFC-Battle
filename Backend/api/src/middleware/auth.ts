import { createMiddleware } from "hono/factory";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";
import { errorResponse } from "../lib/errors";
import type { AppEnv } from "../types";

export type AuthClaims = JWTPayload & {
  sub: string;
  role?: "ATTENDEE" | "STAFF" | string;
};

// JWKS is fetched once per isolate and cached by `jose`. With Workers' isolate
// reuse this means ~one outbound fetch per cold start, not per request.
let jwksCache: ReturnType<typeof createRemoteJWKSet> | null = null;
let jwksCacheUrl = "";
function getJwks(url: string) {
  if (!jwksCache || jwksCacheUrl !== url) {
    jwksCache = createRemoteJWKSet(new URL(url));
    jwksCacheUrl = url;
  }
  return jwksCache;
}

export const requireAuth = createMiddleware<AppEnv>(async (c, next) => {
  const header = c.req.header("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) {
    return errorResponse(c, "UNAUTHORIZED", "Missing bearer token.");
  }

  try {
    const { payload } = await jwtVerify(match[1]!, getJwks(c.env.SSO_JWKS_URL), {
      issuer: c.env.SSO_ISSUER,
      audience: c.env.SSO_AUDIENCE,
    });
    if (typeof payload.sub !== "string" || payload.sub.length === 0) {
      return errorResponse(c, "UNAUTHORIZED", "Token missing sub claim.");
    }
    c.set("claims", payload as AuthClaims);
    await next();
  } catch {
    return errorResponse(c, "UNAUTHORIZED", "Invalid or expired JWT token.");
  }
});

export const requireStaff = createMiddleware<AppEnv>(async (c, next) => {
  const claims = c.get("claims");
  if (!claims || claims.role !== "STAFF") {
    return errorResponse(
      c,
      "SECURITY_VERIFICATION_FAILED",
      "UID mismatch or insufficient permissions.",
    );
  }
  await next();
});
