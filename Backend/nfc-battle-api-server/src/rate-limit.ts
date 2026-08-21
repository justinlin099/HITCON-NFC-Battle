import type { MiddlewareHandler } from "hono";
import { errorResponse } from "./responses";
import type { AppEnv, UserRateLimitBinding } from "./types";

const RATE_LIMIT_WINDOW_SECONDS = 60;

export function limitUserRequests(
  binding: UserRateLimitBinding,
  routeKey: string,
): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const authUser = c.get("authUser");
    const result = await c.env[binding].limit({
      key: `${routeKey}:${authUser.userId}`,
    });
    if (!result.success) {
      c.header("Retry-After", String(RATE_LIMIT_WINDOW_SECONDS));
      return errorResponse(
        c,
        429,
        "RATE_LIMITED",
        "Too many requests for this endpoint. Please retry later.",
      );
    }

    await next();
  };
}
