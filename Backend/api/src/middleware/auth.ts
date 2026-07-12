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
  // Dev-only auth bypass. Requires BOTH gates to avoid accidental enablement
  // in production: ENVIRONMENT must be "development" (set in wrangler.toml,
  // not a secret) AND DEV_BYPASS_AUTH must be "1" (per-developer toggle in
  // .dev.vars). Prod sets ENVIRONMENT="production", so this branch is
  // structurally unreachable on the deployed Worker.
  if (c.env.ENVIRONMENT === "development" && c.env.DEV_BYPASS_AUTH === "1") {
    const sub = c.env.DEV_BYPASS_SUB || "dev_user_001";
    const role = c.env.DEV_BYPASS_ROLE === "STAFF" ? "STAFF" : "ATTENDEE";
    console.warn(`[auth] DEV_BYPASS_AUTH active — sub=${sub} role=${role}`);
    c.set("claims", { sub, role } as AuthClaims);
    await next();
    return;
  }

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
