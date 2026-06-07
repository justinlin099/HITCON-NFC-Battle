import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { AppEnv, ErrorCode } from "./types";

export function success<T>(c: Context<AppEnv>, data: T, status: ContentfulStatusCode = 200) {
  return c.json({ status: "success", data }, status);
}

export function successMessage(
  c: Context<AppEnv>,
  message: string,
  status: ContentfulStatusCode = 200,
) {
  return c.json({ status: "success", message }, status);
}

export function errorResponse(
  c: Context<AppEnv>,
  status: ContentfulStatusCode,
  code: ErrorCode,
  message: string,
) {
  return c.json({ status: "error", code, message }, status);
}
