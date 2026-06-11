import type { MiddlewareHandler } from "hono";
import { errorResponse } from "./responses";
import { timingSafeStringEqual } from "./timing-safe";
import type { AppEnv } from "./types";

export const requireStaffDangerToken: MiddlewareHandler<AppEnv> = async (c, next) => {
  const token = c.req.header("STAFF_DANGER_TOKEN") ?? "";

  if (!c.env.STAFF_DANGER_TOKEN || !timingSafeStringEqual(token, c.env.STAFF_DANGER_TOKEN)) {
    return errorResponse(
      c,
      401,
      "STAFF_DANGER_TOKEN_INVALID",
      "Missing or invalid staff danger token.",
    );
  }

  await next();
};
