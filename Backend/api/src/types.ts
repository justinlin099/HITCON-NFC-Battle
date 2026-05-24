import type { AuthClaims } from "./middleware/auth";

export type Bindings = {
  DB: D1Database;
  SSO_JWKS_URL: string;
  SSO_ISSUER: string;
  SSO_AUDIENCE: string;
  ENVIRONMENT: string;
};

export type Variables = {
  claims: AuthClaims;
};

export type AppEnv = { Bindings: Bindings; Variables: Variables };
