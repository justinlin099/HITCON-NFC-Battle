import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";

// Error codes mirror Backend/README.md "Unified Error Responses".
export type ErrorCode =
  | "UNAUTHORIZED"
  | "SECURITY_VERIFICATION_FAILED"
  | "UID_NOT_FOUND"
  | "TAG_ALREADY_IN_USE"
  | "VALIDATION_ERROR"
  | "INTERNAL_ERROR";

const STATUS: Record<ErrorCode, ContentfulStatusCode> = {
  UNAUTHORIZED: 401,
  SECURITY_VERIFICATION_FAILED: 403,
  UID_NOT_FOUND: 404,
  TAG_ALREADY_IN_USE: 409,
  VALIDATION_ERROR: 400,
  INTERNAL_ERROR: 500,
};

export class ApiError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
  }
}

export function errorResponse(c: Context, code: ErrorCode, message: string) {
  return c.json({ status: "error", code, message }, STATUS[code]);
}

export function ok<T>(c: Context, data: T) {
  return c.json({ status: "success", data });
}
