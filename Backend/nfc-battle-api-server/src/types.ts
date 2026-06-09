export type UserRole = "ATTENDEE" | "STAFF" | "SPONSOR" | "COMMUNITY";

export type ErrorCode =
  | "BAD_REQUEST"
  | "UNAUTHORIZED"
  | "STAFF_DANGER_TOKEN_INVALID"
  | "USER_NOT_FOUND"
  | "PHYSICAL_ID_MISMATCH"
  | "TAG_ALREADY_PAIRED"
  | "SCOREBOARD_ALREADY_FROZEN"
  | "SCOREBOARD_NOT_FROZEN";

export interface AuthenticatedUser {
  userId: string;
  role: UserRole;
  issuer: string;
  audience: string;
  expiresAt: number;
}

export interface JwtPayload {
  sub: string;
  exp: number;
  iss: string;
  aud: string;
  role: UserRole;
}

export interface AppBindings extends CloudflareBindings {
  JWT_SECRET: string;
  STAFF_DANGER_TOKEN: string;
}

export interface AppVariables {
  authUser: AuthenticatedUser;
}

export type AppEnv = {
  Bindings: AppBindings;
  Variables: AppVariables;
};
