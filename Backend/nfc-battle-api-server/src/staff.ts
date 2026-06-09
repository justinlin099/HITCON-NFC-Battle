import type { MiddlewareHandler } from "hono";
import { errorResponse } from "./responses";
import type { AppEnv } from "./types";

export const requireStaffDangerToken: MiddlewareHandler<AppEnv> = async (c, next) => {
  const token = c.req.header("STAFF_DANGER_TOKEN") ?? "";

  if (!c.env.STAFF_DANGER_TOKEN || !constantTimeStringEqual(token, c.env.STAFF_DANGER_TOKEN)) {
    return errorResponse(
      c,
      401,
      "STAFF_DANGER_TOKEN_INVALID",
      "Missing or invalid staff danger token.",
    );
  }

  await next();
};

function constantTimeStringEqual(left: string, right: string) {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  let diff = leftBytes.length ^ rightBytes.length;
  const length = Math.max(leftBytes.length, rightBytes.length);

  for (let i = 0; i < length; i += 1) {
    diff |= (leftBytes[i] ?? 0) ^ (rightBytes[i] ?? 0);
  }

  return diff === 0;
}
