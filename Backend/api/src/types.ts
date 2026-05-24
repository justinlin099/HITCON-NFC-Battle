import type { AuthClaims } from "./middleware/auth";

export type Bindings = {
  DB: D1Database;
  SSO_JWKS_URL: string;
  SSO_ISSUER: string;
  SSO_AUDIENCE: string;
  ENVIRONMENT: string;
  // Dev-only auth bypass. See middleware/auth.ts for the activation
  // condition (both env flags required, plus ENVIRONMENT=development).
  DEV_BYPASS_AUTH?: string;
  DEV_BYPASS_SUB?: string;
  DEV_BYPASS_ROLE?: string;
};

export type Variables = {
  claims: AuthClaims;
};

export type AppEnv = { Bindings: Bindings; Variables: Variables };
